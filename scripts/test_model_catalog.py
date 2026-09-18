import copy
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

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
    def defaults(self, config, generation_config=None):
        return model_catalog.build_runtime("Test", False, "", 6, config, generation_config)["generationDefaults"]

    def test_sampling_aliases_and_mnn_precedence(self):
        defaults = self.defaults({"top_k": 32, "topK": 20, "top_p": 0.8, "topP": 0.9,
                                  "repetition_penalty": 1.2, "penalty": 1.1,
                                  "frequency_penalty": 0.2, "presence_penalty": 0.3,
                                  "penalty_window": 0})
        self.assertEqual(defaults["topK"], 32)
        self.assertEqual(defaults["topP"], 0.8)
        self.assertEqual(defaults["repetitionPenalty"], 1.2)
        self.assertEqual(defaults["frequencyPenalty"], 0.2)
        self.assertEqual(defaults["presencePenalty"], 0.3)
        self.assertEqual(defaults["penaltyWindow"], 0)

    def test_legacy_and_missing_defaults(self):
        self.assertEqual(self.defaults({})["topK"], 40)
        self.assertEqual(self.defaults({"topK": 20, "penalty": 1.1})["repetitionPenalty"], 1.1)

    def test_generation_config_is_secondary_and_output_limit_stays_app_owned(self):
        result = self.defaults({"topK": 20}, {"top_k": 50, "temperature": 0.8,
                                                "max_new_tokens": 32768})
        self.assertEqual(result["topK"], 20)
        self.assertEqual(result["temperature"], 0.8)
        self.assertNotIn("maxNewTokens", result)

    def test_invalid_sampling_values_and_greedy_are_not_silently_converted(self):
        for value in (True, "0.7", float("nan"), float("inf")):
            with self.subTest(value=value), self.assertRaises(model_catalog.CatalogError):
                self.defaults({"temperature": value})
        with self.assertRaises(model_catalog.CatalogError):
            self.defaults({}, {"do_sample": False})
        self.assertEqual(self.defaults({"temperature": None}, {"temperature": 0.8})["temperature"], 0.8)

    def test_build_reads_optional_generation_config_at_resolved_revision(self):
        revision = "a" * 40
        files = [{"Path": name, "Size": 100} for name in
                 ("config.json", "llm_config.json", "llm.mnn", "generation_config.json")]
        args = model_catalog.create_parser().parse_args([
            "add", "Test/Model-MNN", "--min-app-version-code", "1100100"])
        configs = {"config.json": {}, "llm_config.json": {},
                   "generation_config.json": {"temperature": 0.8}}
        with patch.object(model_catalog, "fetch_modelscope_files", return_value=(files, revision)), \
                patch.object(model_catalog, "fetch_repo_json", side_effect=lambda r, v, p: configs[p]) as fetch:
            item = model_catalog.build_item(args)
            fetch.assert_any_call("Test/Model-MNN", revision, "generation_config.json")
            self.assertEqual(item["runtime"]["generationDefaults"]["temperature"], 0.8)
        with patch.object(model_catalog, "fetch_modelscope_files", return_value=(files[:-1], revision)), \
                patch.object(model_catalog, "fetch_repo_json", return_value={}) as fetch:
            model_catalog.build_item(args)
            self.assertEqual(fetch.call_count, 2)

    def test_legacy_rejects_new_runtime_requirement_before_fetch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "catalog.json"
            model_catalog.write_catalog(path, valid_catalog())
            before = path.read_bytes()
            args = model_catalog.create_parser().parse_args([
                "--catalog", str(path), "add", "Test/Model", "--min-app-version-code", "1100100"
            ])
            with patch.object(model_catalog, "build_item") as build:
                with self.assertRaises(model_catalog.CatalogError):
                    model_catalog.run(args)
                build.assert_not_called()
            self.assertEqual(path.read_bytes(), before)

    def test_app_version_validation(self) -> None:
        for value in (0, -1, True, 1.5, "1100100", None, 2147483648):
            with self.subTest(value=value):
                item = valid_item()
                item["minAppVersionCode"] = value
                with self.assertRaises(model_catalog.CatalogError):
                    model_catalog.validate_item(item)
        item = valid_item()
        model_catalog.validate_item(item)
        item["minAppVersionCode"] = 1100100
        model_catalog.validate_item(item)

    def test_defaults_to_current_catalog(self) -> None:
        args = model_catalog.create_parser().parse_args(["validate"])
        self.assertEqual(args.catalog.name, "catalog-v2.json")

    def test_publishing_one_channel_preserves_other_channel(self) -> None:
        for selected_name in ("catalog-v2.json", "catalog.json"):
            with self.subTest(channel=selected_name), tempfile.TemporaryDirectory() as directory:
                current = Path(directory) / "catalog-v2.json"
                legacy = Path(directory) / "catalog.json"
                for path in (current, legacy):
                    model_catalog.write_catalog(path, valid_catalog())
                selected = Path(directory) / selected_name
                other = legacy if selected == current else current
                original = other.read_bytes()
                args = model_catalog.create_parser().parse_args([
                    "--catalog", str(selected), "add", "Test/Remote-Model-MNN", "--min-app-version-code", "1100000"
                ])
                with patch.object(model_catalog, "build_item", return_value=valid_item()):
                    self.assertEqual(model_catalog.run(args), 0)
                self.assertEqual(other.read_bytes(), original)
                self.assertEqual(model_catalog.load_catalog(selected)["catalogVersion"], 2)

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
