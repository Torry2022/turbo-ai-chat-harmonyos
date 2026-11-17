import argparse
from pathlib import Path
import os
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--mnn-source", required=True, type=Path)
parser.add_argument("--cxx", default="g++")
arguments = parser.parse_args()
source = arguments.mnn_source.resolve()
with tempfile.TemporaryDirectory(prefix="h2o-output-test-") as temporary:
    directory = Path(temporary)
    suffix = ".exe" if os.name == "nt" else ""
    fixture = directory / ("fixture" + suffix)
    tool = directory / ("compact-output" + suffix)
    for cpp, executable in [(Path(__file__).with_name("compact_output_test.cpp"), fixture),
                            (Path(__file__).parent.parent / "compact_output.cpp", tool)]:
        subprocess.run([
            arguments.cxx, "-std=c++14", "-O2", "-I", str(source / "schema/current"),
            "-I", str(source / "3rd_party/flatbuffers/include"), str(cpp), "-o", str(executable)
        ], check=True)
    for mode, expected in [("valid", 0), ("no-reshape", 7), ("bad-reshape", 9),
                           ("bad-head", 5), ("truncated", 6), ("malformed", 4)]:
        subprocess.run([str(fixture), temporary, mode], check=True)
        result = subprocess.run([str(tool), str(directory / "source.mnn"),
                                 str(directory / "selected.bin"), str(directory / "output.mnn")])
        assert result.returncode == expected, (mode, result.returncode)
        if mode == "valid":
            subprocess.run([str(fixture), temporary, "verify"], check=True)
    print("PASS missing or invalid output shape, invalid head, truncated weights and malformed graph")
