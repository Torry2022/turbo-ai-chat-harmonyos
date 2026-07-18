#!/usr/bin/env python3
"""Generate and validate Turbo AI Chat's online model catalog."""

from __future__ import annotations

import argparse
import copy
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlparse
from urllib.request import Request, urlopen


SCHEMA_VERSION = 1
MODELSCOPE_ENDPOINT = "https://modelscope.cn"
DEFAULT_CATALOG = Path(__file__).resolve().parents[1] / "model-catalog" / "catalog.json"
ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
DIRECTORY_PATTERN = re.compile(r"^[A-Za-z0-9._-]+$")
REPO_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
REVISION_PATTERN = re.compile(r"^[A-Za-z0-9._-]+$")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{8,64}$")

# These identities change only when a new HAP changes the bundled model profiles.
BUNDLED_MODELS: dict[str, tuple[str, bool, bool]] = {
    "qwen3-4b-instruct": ("Qwen3-4B-Instruct-2507-MNN", False, True),
    "gemma4": ("gemma-4-E2B-it-MNN", True, True),
    "qwen3-vl-4b-instruct": ("Qwen3-VL-4B-Instruct-MNN", True, False),
    "minicpm5-1b": ("MiniCPM5-1B-MNN", False, True),
    "qwen3-0.6b": ("Qwen3-0.6B-MNN", False, False),
    "qwen3-1.7b": ("Qwen3-1.7B-MNN", False, False),
    "qwen2.5-1.5b-instruct": ("Qwen2.5-1.5B-Instruct-MNN", False, False),
    "qwen2.5-3b-instruct": ("Qwen2.5-3B-Instruct-MNN", False, False),
    "qwen3-8b": ("Qwen3-8B-MNN", False, False),
}
PRESET_IDS = {model_id for model_id, (_, _, preset) in BUNDLED_MODELS.items() if preset}


class CatalogError(Exception):
    pass


def normalize_repo(value: str) -> str:
    candidate = value.strip().rstrip("/")
    if candidate.startswith("http://") or candidate.startswith("https://"):
        parsed = urlparse(candidate)
        if parsed.netloc not in {"modelscope.cn", "www.modelscope.cn"}:
            raise CatalogError("模型地址必须来自 modelscope.cn")
        parts = [part for part in parsed.path.split("/") if part]
        if len(parts) >= 3 and parts[0] == "models":
            candidate = f"{parts[1]}/{parts[2]}"
        else:
            raise CatalogError("ModelScope 地址应为 /models/组织/仓库")
    if not REPO_PATTERN.fullmatch(candidate):
        raise CatalogError("ModelScope 仓库应使用 组织/仓库 格式")
    return candidate


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9._-]+", "-", value.lower()).strip("-._")
    if not slug or not ID_PATTERN.fullmatch(slug) or slug.startswith("imported-"):
        raise CatalogError("无法生成安全模型 ID，请通过 --id 显式指定")
    return slug


def is_safe_relative_path(value: str) -> bool:
    if not value or value.startswith("/") or "\\" in value:
        return False
    parts = value.split("/")
    return all(part not in {"", ".", ".."} for part in parts)


def request_json(url: str) -> Any:
    request = Request(url, headers={"Accept": "application/json", "User-Agent": "Turbo-AI-Chat-Catalog-Publisher"})
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def resolve_modelscope_commit(data: dict[str, Any], blobs: list[dict[str, Any]]) -> str:
    latest = data.get("LatestCommitter")
    if not isinstance(latest, dict):
        raise CatalogError("ModelScope 未返回当前版本的提交信息")

    candidate = latest.get("Id") or latest.get("ShortId")
    if not isinstance(candidate, str):
        raise CatalogError("ModelScope 未返回当前版本的提交哈希")
    candidate = candidate.strip().lower()
    if not COMMIT_PATTERN.fullmatch(candidate):
        raise CatalogError("ModelScope 返回了无效的提交哈希")

    revisions = {
        item["Revision"].lower()
        for item in blobs
        if isinstance(item.get("Revision"), str) and COMMIT_PATTERN.fullmatch(item["Revision"].lower())
    }
    matches = {revision for revision in revisions if revision.startswith(candidate)}
    if len(matches) == 1:
        return matches.pop()
    return candidate


def fetch_modelscope_files(repo: str, revision: str) -> tuple[list[dict[str, Any]], str]:
    if not REVISION_PATTERN.fullmatch(revision):
        raise CatalogError("ModelScope revision 只能包含字母、数字、点、下划线和连字符")
    query = urlencode({"Revision": revision, "Recursive": "true"})
    url = f"{MODELSCOPE_ENDPOINT}/api/v1/models/{quote(repo, safe='/')}/repo/files?{query}"
    payload = request_json(url)
    if not isinstance(payload, dict) or payload.get("Success") is not True:
        message = payload.get("Message", "未知错误") if isinstance(payload, dict) else "响应格式无效"
        raise CatalogError(f"读取 ModelScope 文件列表失败：{message}")
    data = payload.get("Data")
    files = data.get("Files") if isinstance(data, dict) else None
    if not isinstance(files, list) or not files:
        raise CatalogError("ModelScope 仓库没有可用文件")
    blobs = [item for item in files if isinstance(item, dict) and item.get("Type") == "blob"]
    resolved_revision = resolve_modelscope_commit(data, blobs)
    return blobs, resolved_revision


def fetch_repo_json(repo: str, revision: str, relative_path: str) -> dict[str, Any]:
    url = (
        f"{MODELSCOPE_ENDPOINT}/models/{quote(repo, safe='/')}/resolve/"
        f"{quote(revision, safe='')}/{quote(relative_path, safe='/')}"
    )
    payload = request_json(url)
    if not isinstance(payload, dict):
        raise CatalogError(f"{relative_path} 不是 JSON 对象")
    return payload


def referenced_paths(value: Any) -> set[str]:
    result: set[str] = set()
    if isinstance(value, dict):
        for child in value.values():
            result.update(referenced_paths(child))
    elif isinstance(value, list):
        for child in value:
            result.update(referenced_paths(child))
    elif isinstance(value, str) and is_safe_relative_path(value):
        result.add(value)
    return result


def is_runtime_file(path: str, references: set[str]) -> bool:
    if path in references:
        return True
    name = PurePosixPath(path).name.lower()
    if name in {"config.json", "llm_config.json", "merges.txt", "vocab.json", "sentencepiece.bpe.model"}:
        return True
    if name.startswith("tokenizer"):
        return True
    return name.endswith((".mnn", ".mnn.weight", ".bin", ".mtok"))


def select_model_files(files: list[dict[str, Any]], references: set[str]) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    for item in files:
        path = item.get("Path")
        size = item.get("Size")
        if not isinstance(path, str) or not isinstance(size, int) or size <= 0:
            continue
        if is_runtime_file(path, references):
            selected.append({"relativePath": path, "sizeBytes": size})
    selected.sort(key=lambda item: item["relativePath"])
    paths = {item["relativePath"] for item in selected}
    if "config.json" not in paths or "llm_config.json" not in paths:
        raise CatalogError("仓库必须包含 config.json 和 llm_config.json")
    return selected


def number(value: Any, fallback: float | int) -> float | int:
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else fallback


def infer_supports_image(mode: str, llm_config: dict[str, Any], files: list[dict[str, Any]]) -> bool:
    if mode == "true":
        return True
    if mode == "false":
        return False
    if llm_config.get("is_visual") is True:
        return True
    return any(PurePosixPath(item["relativePath"]).name.lower().startswith("visual.") for item in files)


def build_runtime(display_name: str, supports_image: bool, system_prompt: str, context_limit: int,
                  config: dict[str, Any]) -> dict[str, Any]:
    prompt = system_prompt.strip()
    if not prompt:
        prompt = f"你是运行在本地设备上的 {display_name}。请始终使用简体中文回答，表达简洁清楚。"
        if supports_image:
            prompt += "用户提供图片时，请结合图片内容准确回答。"
    return {
        "systemPrompt": prompt,
        "contextMessageLimit": context_limit,
        "generationDefaults": {
            "temperature": number(config.get("temperature"), 0.6),
            "topP": number(config.get("topP"), 0.9),
            "topK": number(config.get("topK"), 40),
            "repetitionPenalty": number(config.get("penalty"), 1.05),
            "frequencyPenalty": 0,
            "presencePenalty": 0,
            "penaltyWindow": 256,
        },
    }


def build_item(args: argparse.Namespace) -> dict[str, Any]:
    repo = normalize_repo(args.modelscope_model)
    files, resolved_revision = fetch_modelscope_files(repo, args.revision)
    config = fetch_repo_json(repo, resolved_revision, "config.json")
    llm_config = fetch_repo_json(repo, resolved_revision, "llm_config.json")
    selected_files = select_model_files(files, referenced_paths(config) | referenced_paths(llm_config))

    repo_name = repo.split("/", 1)[1]
    display_name = args.display_name.strip() or re.sub(r"-MNN(?:-.*)?$", "", repo_name, flags=re.IGNORECASE)
    model_id = args.model_id.strip() or slugify(display_name)
    directory_name = args.directory_name.strip() or repo_name
    provider = args.provider.strip() or repo.split("/", 1)[0]
    supports_image = infer_supports_image(args.supports_image, llm_config, selected_files)
    description = args.description.strip() or "来自 ModelScope 的兼容 MNN 端侧模型。"
    capabilities = ["文本", "图片"] if supports_image else ["文本"]
    runtime = build_runtime(display_name, supports_image, args.system_prompt, args.context_message_limit, config)

    return {
        "id": model_id,
        "directoryName": directory_name,
        "displayName": display_name,
        "shortName": display_name,
        "description": description,
        "provider": provider,
        "supportsImage": supports_image,
        "capabilities": capabilities,
        "source": {"type": "modelscope", "repo": repo, "revision": resolved_revision},
        "files": selected_files,
        "runtime": runtime,
    }


def load_catalog(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8-sig") as file:
            catalog = json.load(file)
    except FileNotFoundError as exc:
        raise CatalogError(f"目录文件不存在：{path}") from exc
    except json.JSONDecodeError as exc:
        raise CatalogError(f"目录 JSON 无效：第 {exc.lineno} 行第 {exc.colno} 列") from exc
    if not isinstance(catalog, dict):
        raise CatalogError("目录顶层必须是 JSON 对象")
    return catalog


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CatalogError(message)


def validate_runtime(model_id: str, runtime: Any) -> None:
    require(isinstance(runtime, dict), f"{model_id} 缺少 runtime")
    require(isinstance(runtime.get("systemPrompt"), str) and runtime["systemPrompt"].strip() != "",
            f"{model_id} 的 systemPrompt 无效")
    context_limit = runtime.get("contextMessageLimit")
    require(isinstance(context_limit, int) and not isinstance(context_limit, bool) and context_limit >= 0,
            f"{model_id} 的 contextMessageLimit 无效")
    defaults = runtime.get("generationDefaults")
    if defaults is not None:
        require(isinstance(defaults, dict), f"{model_id} 的 generationDefaults 无效")
        for key, value in defaults.items():
            require(isinstance(value, (int, float)) and not isinstance(value, bool), f"{model_id} 的 {key} 无效")


def validate_item(item: Any) -> None:
    require(isinstance(item, dict), "模型条目必须是 JSON 对象")
    model_id = item.get("id")
    require(isinstance(model_id, str) and ID_PATTERN.fullmatch(model_id) is not None and
            not model_id.startswith("imported-"), "模型 ID 无效")
    directory = item.get("directoryName")
    require(isinstance(directory, str) and DIRECTORY_PATTERN.fullmatch(directory) is not None and
            directory not in {".", ".."}, f"{model_id} 的目录名无效")
    for key in ("displayName", "shortName", "provider"):
        require(isinstance(item.get(key), str) and item[key].strip() != "", f"{model_id} 的 {key} 无效")
    require(isinstance(item.get("description"), str), f"{model_id} 的 description 无效")
    require(isinstance(item.get("supportsImage"), bool), f"{model_id} 的 supportsImage 无效")
    capabilities = item.get("capabilities")
    require(isinstance(capabilities, list) and capabilities and all(isinstance(value, str) and value for value in capabilities),
            f"{model_id} 的 capabilities 无效")
    require(len(capabilities) == len(set(capabilities)), f"{model_id} 的 capabilities 重复")

    source = item.get("source")
    require(isinstance(source, dict) and source.get("type") == "modelscope", f"{model_id} 的来源无效")
    require(isinstance(source.get("repo"), str) and REPO_PATTERN.fullmatch(source["repo"]) is not None,
            f"{model_id} 的 ModelScope 仓库无效")
    require(isinstance(source.get("revision"), str) and COMMIT_PATTERN.fullmatch(source["revision"]) is not None,
            f"{model_id} 的 revision 必须是 ModelScope 提交哈希")

    files = item.get("files")
    require(isinstance(files, list) and files, f"{model_id} 的文件列表为空")
    paths: set[str] = set()
    for file in files:
        require(isinstance(file, dict), f"{model_id} 的文件条目无效")
        path = file.get("relativePath")
        size = file.get("sizeBytes")
        require(isinstance(path, str) and is_safe_relative_path(path), f"{model_id} 的文件路径无效")
        require(path not in paths, f"{model_id} 的文件路径重复：{path}")
        require(isinstance(size, int) and not isinstance(size, bool) and size > 0, f"{model_id} 的文件大小无效：{path}")
        paths.add(path)
    require({"config.json", "llm_config.json"}.issubset(paths), f"{model_id} 缺少基础配置文件")

    bundled = BUNDLED_MODELS.get(model_id)
    if bundled is None:
        require(directory not in {value[0] for value in BUNDLED_MODELS.values()}, f"{model_id} 的目录与内置模型冲突")
        validate_runtime(model_id, item.get("runtime"))
    else:
        require(directory == bundled[0], f"{model_id} 不能修改内置安装目录")
        require(item["supportsImage"] == bundled[1], f"{model_id} 不能修改内置模型模态")
        if item.get("runtime") is not None:
            validate_runtime(model_id, item["runtime"])


def validate_catalog(catalog: dict[str, Any]) -> None:
    require(catalog.get("schemaVersion") == SCHEMA_VERSION, "目录 schemaVersion 不受支持")
    version = catalog.get("catalogVersion")
    require(isinstance(version, int) and not isinstance(version, bool) and version >= 1, "catalogVersion 无效")
    published_at = catalog.get("publishedAt")
    require(isinstance(published_at, str) and published_at.strip() != "", "publishedAt 无效")
    hidden_ids = catalog.get("hiddenIds")
    items = catalog.get("items")
    require(isinstance(hidden_ids, list), "hiddenIds 必须是数组")
    require(isinstance(items, list), "items 必须是数组")

    hidden_seen: set[str] = set()
    for model_id in hidden_ids:
        require(isinstance(model_id, str) and ID_PATTERN.fullmatch(model_id) is not None, "下架模型 ID 无效")
        require(model_id not in PRESET_IDS, f"预置模型不能下架：{model_id}")
        require(model_id not in hidden_seen, f"下架模型 ID 重复：{model_id}")
        hidden_seen.add(model_id)

    ids: set[str] = set()
    directories: set[str] = set()
    for item in items:
        validate_item(item)
        model_id = item["id"]
        directory = item["directoryName"]
        require(model_id not in ids, f"模型 ID 重复：{model_id}")
        require(directory not in directories, f"模型目录重复：{directory}")
        require(model_id not in hidden_seen, f"模型不能同时上架和下架：{model_id}")
        ids.add(model_id)
        directories.add(directory)


def bump_catalog(catalog: dict[str, Any]) -> None:
    catalog["catalogVersion"] += 1
    catalog["publishedAt"] = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def upsert_item(catalog: dict[str, Any], item: dict[str, Any]) -> bool:
    next_catalog = copy.deepcopy(catalog)
    next_catalog["hiddenIds"] = [model_id for model_id in next_catalog["hiddenIds"] if model_id != item["id"]]
    for index, existing in enumerate(next_catalog["items"]):
        if existing["id"] == item["id"]:
            next_catalog["items"][index] = item
            break
    else:
        next_catalog["items"].append(item)
    if next_catalog["hiddenIds"] == catalog["hiddenIds"] and next_catalog["items"] == catalog["items"]:
        return False
    catalog["hiddenIds"] = next_catalog["hiddenIds"]
    catalog["items"] = next_catalog["items"]
    bump_catalog(catalog)
    return True


def hide_item(catalog: dict[str, Any], model_id: str) -> bool:
    require(ID_PATTERN.fullmatch(model_id) is not None, "下架模型 ID 无效")
    require(model_id not in PRESET_IDS, f"预置模型不能下架：{model_id}")
    known_ids = set(BUNDLED_MODELS) | {item["id"] for item in catalog["items"]}
    require(model_id in known_ids or model_id in catalog["hiddenIds"], f"目录中不存在模型：{model_id}")
    next_items = [item for item in catalog["items"] if item["id"] != model_id]
    next_hidden = list(catalog["hiddenIds"])
    if model_id not in next_hidden:
        next_hidden.append(model_id)
    if next_items == catalog["items"] and next_hidden == catalog["hiddenIds"]:
        return False
    catalog["items"] = next_items
    catalog["hiddenIds"] = next_hidden
    bump_catalog(catalog)
    return True


def write_catalog(path: Path, catalog: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    with temp_path.open("w", encoding="utf-8", newline="\n") as file:
        json.dump(catalog, file, ensure_ascii=False, indent=2)
        file.write("\n")
    os.replace(temp_path, path)


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="维护 Turbo AI Chat 在线模型目录")
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG, help="catalog.json 路径")
    subparsers = parser.add_subparsers(dest="command", required=True)

    add = subparsers.add_parser("add", help="从 ModelScope 新增或更新模型")
    add.add_argument("modelscope_model", help="ModelScope URL 或 组织/仓库")
    add.add_argument("--revision", default="master", help="分支、标签或提交；最终会固定到提交哈希")
    add.add_argument("--id", dest="model_id", default="", help="模型 ID，默认根据仓库名生成")
    add.add_argument("--directory-name", default="", help="App 沙箱安装目录名")
    add.add_argument("--display-name", default="", help="模型显示名称")
    add.add_argument("--description", default="", help="模型介绍")
    add.add_argument("--provider", default="", help="提供方，默认使用 ModelScope 组织名")
    add.add_argument("--supports-image", choices=("auto", "true", "false"), default="auto")
    add.add_argument("--system-prompt", default="", help="系统提示词，默认自动生成")
    add.add_argument("--context-message-limit", type=int, default=6)
    add.add_argument("--dry-run", action="store_true", help="只生成并校验，不写入目录")

    hide = subparsers.add_parser("hide", help="下架普通市场模型")
    hide.add_argument("model_id")

    subparsers.add_parser("list", help="列出当前远程目录")
    subparsers.add_parser("validate", help="校验当前远程目录")
    return parser


def run(args: argparse.Namespace) -> int:
    catalog = load_catalog(args.catalog)
    validate_catalog(catalog)

    if args.command == "validate":
        print(f"目录有效：版本 {catalog['catalogVersion']}，上架 {len(catalog['items'])}，下架 {len(catalog['hiddenIds'])}")
        return 0
    if args.command == "list":
        print(f"目录版本：{catalog['catalogVersion']}（{catalog['publishedAt']}）")
        for item in catalog["items"]:
            print(f"上架  {item['id']}  {item['displayName']}  {item['source']['repo']}@{item['source']['revision']}")
        for model_id in catalog["hiddenIds"]:
            print(f"下架  {model_id}")
        return 0
    if args.command == "hide":
        changed = hide_item(catalog, args.model_id)
        validate_catalog(catalog)
        if changed:
            write_catalog(args.catalog, catalog)
            print(f"已下架 {args.model_id}，目录版本更新为 {catalog['catalogVersion']}")
        else:
            print(f"{args.model_id} 已处于下架状态，目录未变化")
        return 0
    if args.command == "add":
        require(args.context_message_limit >= 0, "context-message-limit 不能小于 0")
        item = build_item(args)
        changed = upsert_item(catalog, item)
        validate_catalog(catalog)
        if args.dry_run:
            print(json.dumps(item, ensure_ascii=False, indent=2))
            print(f"校验通过；{'将更新到' if changed else '目录仍为'}版本 {catalog['catalogVersion']}")
        elif changed:
            write_catalog(args.catalog, catalog)
            print(f"已发布 {item['id']}，目录版本更新为 {catalog['catalogVersion']}")
        else:
            print(f"{item['id']} 与当前目录一致，目录未变化")
        return 0
    raise CatalogError("不受支持的命令")


def main() -> int:
    parser = create_parser()
    try:
        return run(parser.parse_args())
    except (CatalogError, HTTPError, URLError, OSError, json.JSONDecodeError) as exc:
        print(f"错误：{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
