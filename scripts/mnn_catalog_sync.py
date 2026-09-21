#!/usr/bin/env python3
"""Scan ModelScope's MNN organization for Turbo AI Chat candidates."""

from __future__ import annotations

import argparse
import json
import re
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

try:
    from scripts import model_catalog
except ModuleNotFoundError:
    import model_catalog  # type: ignore[no-redef]


DEFAULT_ORGANIZATION = "MNN"
DEFAULT_MAX_SIZE_GIB = 12.0
DEFAULT_SHORTLIST_LIMIT = 12
DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parents[1] / "model-catalog" / "candidates"
MODELSCOPE_ENDPOINT = "https://www.modelscope.cn"
UNSUPPORTED_NAME_MARKERS = (
    "embedding",
    "rerank",
    "audio",
    "omni",
    "avatar",
    "diffusion",
    "sana",
    "text-to-image",
    "image-generation",
    "video-generation",
    "speech",
    "whisper",
    "tts",
    "asr",
    "eagle",
    "dflash",
    "qnn",
    "_libs",
    "-npu",
)
SPECIALIZED_NAME_MARKERS = (
    "coder",
    "math",
    "guard",
    "reader",
    "ocr",
    "distill",
    "extract",
    "transcript",
    "-rag-",
    "-tool-",
    "gui-",
    "websailor",
    "vibethinker",
    "hunyuan-mt",
    "hunyuanmt",
    "lingshu",
    "saferl",
)
# Testing priorities, not a statement of runtime compatibility. Review as model
# generations change; repository update timestamps are not model release dates.
CURRENT_FAMILIES = re.compile(r"^(qwen3(?:\.5)?-|gemma-4-|minicpm[45]-|minicpm-v-4(?:[._]5)?-)")
ESTABLISHED_FAMILIES = re.compile(r"^(qwen2(?:\.5)?-|gemma-3-|(?:meta-)?llama-3[.-]|deepseek-r1-|glm-4[.-]|hunyuan-)")
KNOWN_MNN_REPOS = {
    "MNN/Qwen3-4B-Instruct-2507-MNN",
    "MNN/gemma-4-E2B-it-MNN",
    "MNN/Qwen3-VL-4B-Instruct-MNN",
    "MNN/Qwen3-0.6B-MNN",
    "MNN/Qwen3-1.7B-MNN",
    "MNN/Qwen2.5-1.5B-Instruct-MNN",
    "MNN/Qwen2.5-3B-Instruct-MNN",
    "MNN/Qwen3-8B-MNN",
}
HISTORICAL_DEVICE_FAILURES = {
    "MNN/Qwen1.5-1.8B-Chat-MNN": "HarmonyOS 真机加载成功，但生成乱码和重复内容（2026-08-01）",
    "MNN/Hunyuan-0.5B-Instruct-MNN": "HarmonyOS 真机生成冗长，且最终答案暴露原始 answer 标签（2026-08-01）",
}


class SyncError(Exception):
    pass


def request_json(url: str, method: str = "GET", body: dict[str, Any] | None = None) -> Any:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "User-Agent": "Turbo-AI-Chat-MNN-Candidate-Scanner",
    }
    request = Request(url, data=data, headers=headers, method=method)
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def fetch_organization_models(organization: str) -> list[dict[str, Any]]:
    payload = request_json(
        f"{MODELSCOPE_ENDPOINT}/api/v1/models",
        method="PUT",
        body={"Path": organization, "PageNumber": 1, "PageSize": 500},
    )
    data = payload.get("Data") if isinstance(payload, dict) else None
    models = data.get("Models") if isinstance(data, dict) else None
    total = data.get("TotalCount") if isinstance(data, dict) else None
    if not isinstance(models, list) or not all(isinstance(item, dict) for item in models):
        raise SyncError("ModelScope 未返回有效的组织模型列表")
    if isinstance(total, int) and total > len(models):
        raise SyncError(f"组织共有 {total} 个模型，但接口只返回了 {len(models)} 个")
    return models


def model_repo(model: dict[str, Any]) -> str:
    path = model.get("Path")
    name = model.get("Name")
    if not isinstance(path, str) or not isinstance(name, str):
        raise SyncError("模型元数据缺少 Path 或 Name")
    return model_catalog.normalize_repo(f"{path}/{name}")


def task_names(model: dict[str, Any]) -> list[str]:
    tasks = model.get("Tasks")
    if not isinstance(tasks, list):
        return []
    return [task["Name"] for task in tasks if isinstance(task, dict) and isinstance(task.get("Name"), str)]


def reason(code: str, message: str) -> dict[str, str]:
    return {"code": code, "message": message}


def metadata_rejections(model: dict[str, Any], max_bytes: int) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    name = str(model.get("Name", ""))
    lowered = name.lower()
    tasks = task_names(model)

    if model.get("IsAccessible") == 0 or model.get("IsPublished") == 0:
        result.append(reason("not_accessible", "仓库当前不可公开访问"))
    if any(marker in lowered for marker in UNSUPPORTED_NAME_MARKERS):
        result.append(reason("unsupported_purpose", "仓库名称表明它不是当前文本/图片聊天链路"))
    if (model.get("IsPreTrain") == 1 or "-base-" in lowered or lowered.endswith("-base-mnn")) and not any(
        marker in lowered for marker in ("chat", "instruct")
    ):
        result.append(reason("base_model", "基础模型未声明对话微调"))
    if tasks and "text-generation" not in tasks:
        result.append(reason("unsupported_task", f"任务类型不受支持：{', '.join(tasks)}"))
    # Repository size may include non-runtime assets. Apply the size limit only
    # after resolving the actual runtime files.
    return result


def retry(operation: Callable[[], Any], attempts: int = 3) -> Any:
    for attempt in range(attempts):
        try:
            return operation()
        except HTTPError as exc:
            if exc.code < 500 and exc.code != 429:
                raise
            error: Exception = exc
        except (URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
            error = exc
        if attempt + 1 < attempts:
            time.sleep(0.5 * (attempt + 1))
    raise error


def is_legacy_chatml(llm_config: dict[str, Any]) -> bool:
    template = llm_config.get("prompt_template")
    return isinstance(template, str) and all(
        marker in template for marker in ("%s", "<|im_start|>user", "<|im_start|>assistant", "<|im_end|>")
    )


def has_chat_template(llm_config: dict[str, Any]) -> bool:
    jinja = llm_config.get("jinja")
    template = jinja.get("chat_template") if isinstance(jinja, dict) else None
    return isinstance(template, str) and bool(template.strip()) or is_legacy_chatml(llm_config)


def config_references(config: dict[str, Any], llm_config: dict[str, Any]) -> set[str]:
    references: set[str] = set()
    tied_embeddings = isinstance(llm_config.get("tie_embeddings"), list) and bool(llm_config["tie_embeddings"])
    for key in (
        "llm_model",
        "llm_weight",
        "visual_model",
        "visual_weight",
        "audio_model",
        "audio_weight",
        "embeddings",
        "tokenizer_file",
    ):
        value = config.get(key)
        if isinstance(value, str) and model_catalog.is_safe_relative_path(value):
            references.add(value)
    embedding_file = config.get("embedding_file")
    if not tied_embeddings and isinstance(embedding_file, str) and model_catalog.is_safe_relative_path(embedding_file):
        references.add(embedding_file)
    return references


def static_compatibility(
    config: dict[str, Any],
    llm_config: dict[str, Any],
    selected_files: list[dict[str, Any]],
    max_bytes: int,
) -> tuple[list[dict[str, str]], list[dict[str, str]], bool]:
    failures: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []
    paths = {item["relativePath"] for item in selected_files}
    names = {PurePosixPath(path).name.lower() for path in paths}
    llm_model = config.get("llm_model")
    jinja = config.get("jinja")
    jinja_context = jinja.get("context") if isinstance(jinja, dict) else None

    if not has_chat_template(llm_config):
        warnings.append(reason("template_review_required", "未识别到可直接使用的聊天模板，需人工核对，不能据此认定模型不兼容"))
    if isinstance(jinja_context, dict) and jinja_context.get("enable_thinking") is True:
        warnings.append(reason("thinking_enabled_by_default", "默认开启思考；需验证最终答案及输出预算，不作为淘汰条件"))
    if not isinstance(llm_model, str) or not llm_model.strip():
        failures.append(reason("llm_model_missing", "config.json 缺少 llm_model"))
    if not any(name.endswith(".mnn") for name in names):
        failures.append(reason("mnn_graph_missing", "缺少 .mnn 模型图"))
    if not any(name.startswith("tokenizer") or name in {"sentencepiece.bpe.model", "vocab.json"} for name in names):
        failures.append(reason("tokenizer_missing", "缺少 tokenizer 文件"))

    missing_references = sorted(config_references(config, llm_config) - paths)
    if missing_references:
        failures.append(reason("referenced_file_missing", f"配置引用文件不存在：{', '.join(missing_references)}"))

    supports_image = model_catalog.infer_supports_image("auto", llm_config, selected_files)
    if supports_image and not any(name.startswith("visual.") for name in names):
        failures.append(reason("visual_files_missing", "声明了图片能力但缺少视觉模型文件"))

    runtime_bytes = sum(item["sizeBytes"] for item in selected_files)
    if runtime_bytes > max_bytes:
        failures.append(reason("runtime_too_large", f"运行文件合计超过 {format_bytes(max_bytes)}"))
    if any(name.startswith("audio.") for name in names):
        warnings.append(reason("audio_files_ignored", "仓库包含音频模型文件，当前 App 仅使用其文本/图片能力"))
    warnings.append(reason("device_smoke_required", "仍需使用当前 App 的 MNN Runtime 在 HarmonyOS 真机上验证加载和生成"))
    return failures, warnings, supports_image


def build_candidate(model: dict[str, Any], max_bytes: int) -> dict[str, Any]:
    repo = model_repo(model)
    files, revision = retry(lambda: model_catalog.fetch_modelscope_files(repo, "master"))
    config = retry(lambda: model_catalog.fetch_repo_json(repo, revision, "config.json"))
    llm_config = retry(lambda: model_catalog.fetch_repo_json(repo, revision, "llm_config.json"))
    generation_config = (
        retry(lambda: model_catalog.fetch_repo_json(repo, revision, "generation_config.json"))
        if any(file.get("Path") == "generation_config.json" for file in files) else None
    )
    references = model_catalog.referenced_paths(config) | model_catalog.referenced_paths(llm_config)
    selected_files = model_catalog.select_model_files(files, references)
    failures, warnings, supports_image = static_compatibility(config, llm_config, selected_files, max_bytes)
    if repo in HISTORICAL_DEVICE_FAILURES:
        warnings.append(reason("historical_device_failure", HISTORICAL_DEVICE_FAILURES[repo] +
                               "；旧测试未记录运行时和模型提交，不能据此认定当前版本不兼容，需人工决定是否重测"))
    if repo == "MNN/Qwen3.5-0.8B-MNN":
        warnings.append(reason("output_budget_review", "旧测试在 512 tokens 内未生成最终答案，需复核预算，不等同于无法运行"))

    repo_name = repo.split("/", 1)[1]
    display_name = repo_name[:-4] if repo_name.lower().endswith("-mnn") else repo_name
    description = model.get("Description")
    if not isinstance(description, str) or not description.strip():
        description = "来自 MNN 官方组织的端侧模型候选，发布前需完成 HarmonyOS 真机验证。"
    item = {
        "id": model_catalog.slugify(display_name),
        "directoryName": repo_name,
        "displayName": display_name,
        "shortName": display_name,
        "description": description.strip(),
        "provider": repo.split("/", 1)[0],
        "supportsImage": supports_image,
        "capabilities": ["文本", "图片"] if supports_image else ["文本"],
        "source": {"type": "modelscope", "repo": repo, "revision": revision},
        "files": selected_files,
        "runtime": model_catalog.build_runtime(display_name, supports_image, "", 6, config, generation_config),
    }
    return {
        "repo": repo,
        "downloads": model.get("Downloads", 0),
        "lastUpdatedTime": model.get("LastUpdatedTime", 0),
        "license": model.get("License", ""),
        "tasks": task_names(model),
        "repositoryBytes": model.get("StorageSize", 0),
        "runtimeBytes": sum(file["sizeBytes"] for file in selected_files),
        "warnings": warnings,
        "failures": failures,
        "catalogItem": item,
    }


def rejected_entry(model: dict[str, Any], reasons: list[dict[str, str]]) -> dict[str, Any]:
    try:
        repo = model_repo(model)
    except (SyncError, model_catalog.CatalogError):
        repo = str(model.get("Name", "未知仓库"))
    return {
        "repo": repo,
        "downloads": model.get("Downloads", 0),
        "repositoryBytes": model.get("StorageSize", 0),
        "reasons": reasons,
    }


def scan_models(models: list[dict[str, Any]], max_bytes: int, workers: int) -> dict[str, Any]:
    rejected: list[dict[str, Any]] = []
    pending: list[dict[str, Any]] = []
    for model in models:
        reasons = metadata_rejections(model, max_bytes)
        if reasons:
            rejected.append(rejected_entry(model, reasons))
        else:
            pending.append(model)

    candidates: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {executor.submit(build_candidate, model, max_bytes): model for model in pending}
        for future in as_completed(futures):
            model = futures[future]
            try:
                result = future.result()
                if result["failures"]:
                    rejected.append(rejected_entry(model, result["failures"]))
                else:
                    candidates.append(result)
            except (SyncError, model_catalog.CatalogError, HTTPError, URLError, OSError, json.JSONDecodeError) as exc:
                if isinstance(exc, HTTPError) and exc.code == 404:
                    rejected.append(rejected_entry(
                        model,
                        [reason("required_file_missing", "仓库缺少标准 MNN 对话模型入口文件")],
                    ))
                else:
                    errors.append({"repo": model_repo(model), "message": str(exc)})

    candidates.sort(key=lambda item: (-safe_int(item.get("downloads")), item["repo"].lower()))
    rejected.sort(key=lambda item: item["repo"].lower())
    errors.sort(key=lambda item: item["repo"].lower())
    return {"candidates": candidates, "rejected": rejected, "errors": errors}


def safe_int(value: Any) -> int:
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def format_bytes(size: int) -> str:
    value = float(size)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if value < 1024 or unit == "GiB":
            return f"{value:.2f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024
    return f"{size} B"


def catalogued_repos() -> set[str]:
    repos = set(KNOWN_MNN_REPOS)
    with model_catalog.DEFAULT_CATALOG.open(encoding="utf-8") as handle:
        catalog = json.load(handle)
    for item in catalog.get("items", []):
        source = item.get("source") if isinstance(item, dict) else None
        repo = source.get("repo") if isinstance(source, dict) else None
        if isinstance(repo, str):
            repos.add(repo)
    return repos


def shortlist_candidates(
    candidates: list[dict[str, Any]],
    limit: int,
    known_repos: set[str] | None = None,
) -> list[dict[str, Any]]:
    published_repos = catalogued_repos() if known_repos is None else known_repos
    result: list[dict[str, Any]] = []
    for candidate in candidates:
        repo = candidate["repo"]
        lowered = repo.lower()
        candidate["alreadyCatalogued"] = repo in published_repos
        candidate["specialized"] = any(marker in lowered for marker in SPECIALIZED_NAME_MARKERS)
        name = lowered.split("/", 1)[-1]
        candidate["priorityTier"] = 0 if CURRENT_FAMILIES.match(name) else 1 if ESTABLISHED_FAMILIES.match(name) else 2
        candidate["needsTemplateReview"] = any(
            warning["code"] == "template_review_required" for warning in candidate.get("warnings", [])
        )
        candidate["needsRetestReview"] = any(
            warning["code"] == "historical_device_failure" for warning in candidate.get("warnings", [])
        )
        if (not candidate["alreadyCatalogued"] and not candidate["specialized"]
                and candidate["priorityTier"] < 2 and not candidate["needsTemplateReview"]
                and not candidate["needsRetestReview"]):
            result.append(candidate)
    result.sort(key=lambda item: (item["priorityTier"], -safe_int(item.get("downloads")), item["repo"].lower()))
    return result[:limit]


def build_report(
    organization: str,
    models: list[dict[str, Any]],
    result: dict[str, Any],
    max_bytes: int,
    shortlist_limit: int,
) -> dict[str, Any]:
    shortlist = shortlist_candidates(result["candidates"], shortlist_limit)
    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "source": {"type": "modelscope-organization", "organization": organization},
        "policy": {
            "maxRuntimeBytes": max_bytes,
            "supportedTasks": ["text-generation"],
            "requiresChatTemplateReview": True,
            "shortlistOrder": "current-mainstream, established-mainstream, downloads-within-tier",
            "thinkingIsRejection": False,
            "fileSizeIsNotMemoryEstimate": True,
            "requiresDeviceSmoke": True,
            "publishesAutomatically": False,
            "shortlistLimit": shortlist_limit,
        },
        "summary": {
            "total": len(models),
            "shortlist": len(shortlist),
            "candidates": len(result["candidates"]),
            "rejected": len(result["rejected"]),
            "errors": len(result["errors"]),
        },
        "shortlist": shortlist,
        **result,
    }


def markdown_report(report: dict[str, Any]) -> str:
    summary = report["summary"]
    lines = [
        "# MNN 官方模型候选扫描",
        "",
        f"生成时间：`{report['generatedAt']}`",
        "",
        f"扫描 {summary['total']} 个模型：优先真机队列 {summary['shortlist']}，静态候选 {summary['candidates']}，"
        f"淘汰 {summary['rejected']}，错误 {summary['errors']}。",
        "",
        "> 静态候选不会自动进入正式模型广场；仍需完成 HarmonyOS 真机冒烟测试。",
        "",
        "## 优先真机队列",
        "",
        "| ModelScope 仓库 | 运行文件 | 下载量 | 能力 | 注意事项 |",
        "| --- | ---: | ---: | --- | --- |",
    ]
    for candidate in report["shortlist"]:
        item = candidate["catalogItem"]
        warning_text = "；".join(value["message"] for value in candidate["warnings"])
        lines.append(
            f"| `{candidate['repo']}` | {format_bytes(candidate['runtimeBytes'])} | "
            f"{safe_int(candidate['downloads'])} | {'、'.join(item['capabilities'])} | {warning_text} |"
        )
    if not report["shortlist"]:
        lines.append("| — | — | — | — | 没有通过静态筛选的模型 |")

    lines.extend([
        "",
        "## 全部静态候选",
        "",
        "完整条目、固定提交和文件清单见 `mnn-candidates.json`。优先较新主流系列，其次仍有补充价值的常用系列；同层内才参考魔搭下载量。",
        "已收录、专用、过老或非本轮主流范围的模型不进入优先队列；模板疑点留作人工复核，不标为运行不兼容。默认思考不阻止进入队列。",
        "文件上限不是内存需求估算；下载和加载前仍需检查设备可用内存，控制上下文与输出预算。",
    ])

    reason_counts = Counter(
        item["code"] for rejected in report["rejected"] for item in rejected["reasons"]
    )
    lines.extend(["", "## 淘汰原因统计", "", "| 原因代码 | 数量 |", "| --- | ---: |"])
    for code, count in sorted(reason_counts.items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"| `{code}` | {count} |")
    if not reason_counts:
        lines.append("| — | 0 |")

    lines.extend(["", "## 扫描错误", ""])
    if report["errors"]:
        for item in report["errors"]:
            lines.append(f"- `{item['repo']}`：{item['message']}")
    else:
        lines.append("无。")
    lines.append("")
    return "\n".join(lines)


def write_reports(output_dir: Path, report: dict[str, Any]) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    json_path = output_dir / "mnn-candidates.json"
    markdown_path = output_dir / "mnn-candidates.md"
    json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    markdown_path.write_text(markdown_report(report), encoding="utf-8", newline="\n")
    return json_path, markdown_path


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="扫描 ModelScope MNN 官方组织并生成模型广场候选报告")
    parser.add_argument("--organization", default=DEFAULT_ORGANIZATION)
    parser.add_argument("--max-size-gib", type=float, default=DEFAULT_MAX_SIZE_GIB)
    parser.add_argument("--shortlist-limit", type=int, default=DEFAULT_SHORTLIST_LIMIT)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    return parser


def main() -> int:
    args = create_parser().parse_args()
    if args.max_size_gib <= 0:
        print("错误：max-size-gib 必须大于 0")
        return 1
    if args.workers <= 0 or args.workers > 32:
        print("错误：workers 必须在 1 到 32 之间")
        return 1
    if args.shortlist_limit <= 0:
        print("错误：shortlist-limit 必须大于 0")
        return 1
    try:
        models = fetch_organization_models(args.organization)
        max_bytes = int(args.max_size_gib * 1024**3)
        result = scan_models(models, max_bytes, args.workers)
        report = build_report(args.organization, models, result, max_bytes, args.shortlist_limit)
        json_path, markdown_path = write_reports(args.output_dir, report)
        summary = report["summary"]
        print(
            f"扫描完成：共 {summary['total']}，优先队列 {summary['shortlist']}，候选 {summary['candidates']}，"
            f"淘汰 {summary['rejected']}，错误 {summary['errors']}"
        )
        print(json_path)
        print(markdown_path)
        return 0
    except (SyncError, model_catalog.CatalogError, HTTPError, URLError, OSError, json.JSONDecodeError) as exc:
        print(f"错误：{exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
