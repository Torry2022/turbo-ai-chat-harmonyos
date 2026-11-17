"""Extract the official H2O decision labels without changing their FP16 weights."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


HEAD_OFFSET = 3793581568
HEAD_BYTES = 1271398400
ROW_BYTES = 2560 * 2
SOURCE_HASHES = {
    "llm.mnn": "ed7abfee65f4596a85be200274b795a98ab5553ee199db56a1c9301f686a7a0f",
    "llm.mnn.weight": "bfad394dca0c470ac85692b1ee746d1a697998b18524f3c807c6af0f9ff8dbde",
    "tokenizer.mtok": "a3a67a5f90a39d61caa36682742661fdc924bd888942221506802a4599f9d63d",
}


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def convert(source, output, mnn_source, compiler):
    source, output, mnn_source = source.resolve(), output.resolve(), mnn_source.resolve()
    if output.exists() or source == output or source in output.parents:
        raise ValueError("Choose a new output directory outside the source model")
    for name, expected in SOURCE_HASHES.items():
        if sha256(source / name) != expected:
            raise ValueError(f"Source model checksum does not match the supported INT8 package: {name}")
    if (source / "llm.mnn.weight").stat().st_size != HEAD_OFFSET + HEAD_BYTES:
        raise ValueError("The full output head must be the final block in the weight file")
    contract = (Path(__file__).parent / "h2o_contract.h").read_text(encoding="utf-8")
    match = re.search(r"labelTokens\s*=\s*\{([^}]+)\}", contract)
    if match is None:
        raise ValueError("Missing H2O label-token contract")
    labels = [int(value) for value in match.group(1).split(",") if value.strip()]
    if len(labels) != 255 or len(set(labels)) != 255 or min(labels) < 0 or max(labels) >= 248320:
        raise ValueError("Invalid H2O label-token contract")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="h2o-compact-", dir=output.parent) as temporary:
        work = Path(temporary)
        package = work / "package"
        package.mkdir()
        selected = work / "selected-fp16.bin"
        with (source / "llm.mnn.weight").open("rb") as weights, selected.open("wb") as rows:
            for token in labels:
                weights.seek(HEAD_OFFSET + token * ROW_BYTES)
                row = weights.read(ROW_BYTES)
                if len(row) != ROW_BYTES:
                    raise ValueError("Truncated output-head row")
                rows.write(row)
        tool = work / ("compact-output.exe" if os.name == "nt" else "compact-output")
        subprocess.run([
            compiler, "-std=c++14", "-O2", "-I", str(mnn_source / "schema/current"),
            "-I", str(mnn_source / "3rd_party/flatbuffers/include"),
            str(Path(__file__).with_name("compact_output.cpp")), "-o", str(tool)
        ], check=True)
        subprocess.run([str(tool), str(source / "llm.mnn"), str(selected),
                        str(package / "llm.mnn")], check=True)
        with (source / "llm.mnn.weight").open("rb") as original, \
                (package / "llm.mnn.weight").open("wb") as compact:
            remaining = HEAD_OFFSET
            while remaining:
                block = original.read(min(remaining, 8 * 1024 * 1024))
                if not block:
                    raise ValueError("Truncated language-model weights")
                compact.write(block)
                remaining -= len(block)
        for name in ["llm_config.json", "embeddings_bf16.bin", "tokenizer.mtok",
                     "visual.mnn", "visual.mnn.weight", "LICENSE", "NOTICE", "configuration.json"]:
            path = source / name
            if path.suffix in [".bin", ".weight"]:
                try:
                    os.link(path, package / name)
                    continue
                except OSError:
                    pass
            shutil.copy2(path, package / name)
        config = json.loads((source / "config.json").read_text(encoding="utf-8"))
        config["decision_output"] = "h2o-labels-v1"
        (package / "config.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
        conversion = json.loads((source / "conversion.json").read_text(encoding="utf-8"))
        conversion["conversion"]["output_head"] = "FP16, 255 official decision-label rows"
        conversion["decision"]["output_format"] = "h2o-labels-v1"
        conversion["decision"]["output_token_ids"] = labels
        conversion["decision"]["full_head_source_sha256"] = SOURCE_HASHES["llm.mnn.weight"]
        (package / "conversion.json").write_text(
            json.dumps(conversion, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        manifest = [{"name": path.name, "size": path.stat().st_size, "sha256": sha256(path)}
                    for path in sorted(package.iterdir()) if path.is_file()]
        (package / "SHA256SUMS").write_text(
            "".join(f"{item['sha256']}  {item['name']}\n" for item in manifest), encoding="utf-8")
        package.rename(output)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mnn-source", required=True, type=Path)
    parser.add_argument("--cxx", default="g++")
    arguments = parser.parse_args()
    result = convert(arguments.source, arguments.output, arguments.mnn_source, arguments.cxx)
    print(json.dumps({"output": str(arguments.output.resolve()), "files": result}, indent=2))
