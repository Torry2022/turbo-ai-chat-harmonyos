import copy
import unittest

from scripts import model_catalog


def valid_item(model_id: str = "remote-model") -> dict:
    return {
        "id": model_id,
        "directoryName": "Remote-Model-MNN",
        "displayName": "Remote Model",
        "shortName": "Remote Model",
        "description": "测试模型",
        "provider": "Test",
        "supportsImage": False,
        "capabilities": ["文本"],
        "source": {
            "type": "modelscope",
            "repo": "Test/Remote-Model-MNN",
            "revision": "0123456789abcdef0123456789abcdef01234567",
        },
        "files": [
            {"relativePath": "config.json", "sizeBytes": 100},
            {"relativePath": "llm_config.json", "sizeBytes": 100},
            {"relativePath": "llm.mnn", "sizeBytes": 100},
            {"relativePath": "llm.mnn.weight", "sizeBytes": 100},
        ],
        "runtime": {
            "systemPrompt": "你是测试模型。",
            "contextMessageLimit": 6,
            "generationDefaults": {"temperature": 0.6, "topP": 0.9, "topK": 40},
        },
    }


def valid_catalog() -> dict:
    return {
        "schemaVersion": 1,
        "catalogVersion": 1,
        "publishedAt": "2026-07-18T12:00:00+08:00",
        "hiddenIds": [],
        "items": [],
    }


class ModelCatalogPublisherTest(unittest.TestCase):
    def test_normalize_modelscope_url(self) -> None:
        self.assertEqual(
            model_catalog.normalize_repo("https://modelscope.cn/models/Test/Remote-Model-MNN"),
            "Test/Remote-Model-MNN",
        )

    def test_selects_runtime_files_and_skips_repository_docs(self) -> None:
        files = [
            {"Path": "config.json", "Size": 100},
            {"Path": "llm_config.json", "Size": 200},
            {"Path": "llm.mnn", "Size": 300},
            {"Path": "llm.mnn.json", "Size": 400},
            {"Path": "llm.mnn.weight", "Size": 500},
            {"Path": "tokenizer.txt", "Size": 600},
            {"Path": "README.md", "Size": 700},
        ]
        selected = model_catalog.select_model_files(files, set())
        paths = [item["relativePath"] for item in selected]
        self.assertEqual(
            paths,
            ["config.json", "llm.mnn", "llm.mnn.weight", "llm_config.json", "tokenizer.txt"],
        )

    def test_resolves_head_commit_when_files_have_mixed_last_revisions(self) -> None:
        head = "83ee97c66e841048bedc5c02c15ce2f3ed259feb"
        older = "f194f50981eaaa6019bbec5049a4c7e1fd294110"
        data = {"LatestCommitter": {"Id": "", "ShortId": head[:8]}}
        blobs = [{"Revision": older}, {"Revision": head}]
        self.assertEqual(model_catalog.resolve_modelscope_commit(data, blobs), head)

    def test_upsert_bumps_version_and_unhides_model(self) -> None:
        catalog = valid_catalog()
        catalog["hiddenIds"] = ["remote-model"]
        changed = model_catalog.upsert_item(catalog, valid_item())
        self.assertTrue(changed)
        self.assertEqual(catalog["catalogVersion"], 2)
        self.assertEqual(catalog["hiddenIds"], [])
        model_catalog.validate_catalog(catalog)

    def test_rejects_hiding_preset_model(self) -> None:
        with self.assertRaises(model_catalog.CatalogError):
            model_catalog.hide_item(valid_catalog(), "qwen3-4b-instruct")

    def test_rejects_hiding_unknown_model(self) -> None:
        with self.assertRaises(model_catalog.CatalogError):
            model_catalog.hide_item(valid_catalog(), "unknown-model")

    def test_rejects_path_traversal(self) -> None:
        catalog = valid_catalog()
        item = valid_item()
        item["files"][0]["relativePath"] = "../config.json"
        catalog["items"] = [item]
        with self.assertRaises(model_catalog.CatalogError):
            model_catalog.validate_catalog(catalog)

    def test_identical_upsert_does_not_bump_version(self) -> None:
        catalog = valid_catalog()
        item = valid_item()
        catalog["items"] = [copy.deepcopy(item)]
        changed = model_catalog.upsert_item(catalog, item)
        self.assertFalse(changed)
        self.assertEqual(catalog["catalogVersion"], 1)


if __name__ == "__main__":
    unittest.main()
