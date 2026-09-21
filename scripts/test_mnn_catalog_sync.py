import unittest
from unittest.mock import patch

from scripts import mnn_catalog_sync


def metadata(name: str = "Qwen3-0.6B-MNN", size: int = 400_000_000) -> dict:
    return {
        "Path": "MNN",
        "Name": name,
        "StorageSize": size,
        "Tasks": [{"Name": "text-generation"}],
        "Downloads": 100,
        "IsAccessible": 1,
        "IsPublished": 1,
        "IsPreTrain": 0,
    }


def runtime_files() -> list[dict]:
    return [
        {"relativePath": "config.json", "sizeBytes": 100},
        {"relativePath": "llm_config.json", "sizeBytes": 200},
        {"relativePath": "tokenizer.txt", "sizeBytes": 300},
        {"relativePath": "llm.mnn", "sizeBytes": 400},
        {"relativePath": "llm.mnn.weight", "sizeBytes": 500},
    ]


class MnnCatalogSyncTest(unittest.TestCase):
    def test_rejects_unsupported_audio_model_before_fetching_files(self) -> None:
        rejected = mnn_catalog_sync.metadata_rejections(metadata("Fun-Audio-Chat-8B-MNN"), 8 * 1024**3)
        self.assertIn("unsupported_purpose", {item["code"] for item in rejected})

    def test_repository_size_does_not_replace_runtime_size(self) -> None:
        rejected = mnn_catalog_sync.metadata_rejections(metadata(size=5 * 1024**3), 4 * 1024**3)
        self.assertEqual(rejected, [])

    def test_historical_device_failure_is_not_metadata_rejection(self) -> None:
        for name in (
            "Qwen1.5-1.8B-Chat-MNN",
            "Hunyuan-0.5B-Instruct-MNN",
        ):
            with self.subTest(name=name):
                rejected = mnn_catalog_sync.metadata_rejections(metadata(name), 4 * 1024**3)
                self.assertEqual(rejected, [])

    def test_minicpm_visual_family_names(self) -> None:
        for name in ("MiniCPM-V-4-MNN", "MiniCPM-V-4_5-MNN", "MiniCPM-V-4.5-MNN"):
            with self.subTest(name=name):
                candidate = {"repo": "MNN/" + name, "downloads": 1}
                self.assertEqual(mnn_catalog_sync.shortlist_candidates([candidate], 12, set()), [candidate])
                self.assertEqual(candidate["priorityTier"], 0)
        candidate = {"repo": "MNN/MiniCPM-V-40-MNN", "downloads": 100}
        self.assertEqual(mnn_catalog_sync.shortlist_candidates([candidate], 12, set()), [])

    def test_accepts_jinja_chat_model_for_device_smoke_queue(self) -> None:
        config = {"llm_model": "llm.mnn", "llm_weight": "llm.mnn.weight", "tokenizer_file": "tokenizer.txt"}
        llm_config = {"jinja": {"chat_template": "{{ messages }}"}}
        failures, warnings, supports_image = mnn_catalog_sync.static_compatibility(
            config, llm_config, runtime_files(), 4 * 1024**3
        )
        self.assertEqual(failures, [])
        self.assertFalse(supports_image)
        self.assertIn("device_smoke_required", {item["code"] for item in warnings})

    def test_missing_chat_template_requires_review_not_rejection(self) -> None:
        config = {"llm_model": "llm.mnn", "tokenizer_file": "tokenizer.txt"}
        failures, warnings, _ = mnn_catalog_sync.static_compatibility(config, {}, runtime_files(), 4 * 1024**3)
        self.assertEqual(failures, [])
        self.assertIn("template_review_required", {item["code"] for item in warnings})

    def test_default_thinking_is_warning_not_rejection(self) -> None:
        config = {
            "llm_model": "llm.mnn",
            "tokenizer_file": "tokenizer.txt",
            "jinja": {"context": {"enable_thinking": True}},
        }
        llm_config = {"jinja": {"chat_template": "{{ messages }}"}}
        failures, warnings, _ = mnn_catalog_sync.static_compatibility(
            config, llm_config, runtime_files(), 4 * 1024**3
        )
        self.assertEqual(failures, [])
        self.assertIn("thinking_enabled_by_default", {item["code"] for item in warnings})
        self.assertEqual(mnn_catalog_sync.metadata_rejections(metadata("Qwen3.5-0.8B-MNN"), 4 * 1024**3), [])

    def test_runtime_size_limit_still_applies(self) -> None:
        failures, _, _ = mnn_catalog_sync.static_compatibility(
            {"llm_model": "llm.mnn"}, {"jinja": {"chat_template": "{{ messages }}"}}, runtime_files(), 1000
        )
        self.assertIn("runtime_too_large", {item["code"] for item in failures})

    def test_current_models_precede_popular_older_models(self) -> None:
        candidates = [
            {"repo": "MNN/Qwen2.5-7B-Instruct-MNN", "downloads": 10000, "lastUpdatedTime": 999},
            {"repo": "MNN/Qwen3.5-4B-MNN", "downloads": 100, "lastUpdatedTime": 1},
            {"repo": "MNN/Qwen3-14B-MNN", "downloads": 200, "lastUpdatedTime": 0},
        ]
        result = mnn_catalog_sync.shortlist_candidates(candidates, 12, set())
        self.assertEqual([item["repo"] for item in result], [
            "MNN/Qwen3-14B-MNN", "MNN/Qwen3.5-4B-MNN", "MNN/Qwen2.5-7B-Instruct-MNN"
        ])

    def test_old_obscure_and_unreviewed_models_stay_out_of_queue(self) -> None:
        candidates = [
            {"repo": "MNN/Qwen1.5-7B-Chat-MNN", "downloads": 10000},
            {"repo": "MNN/LFM2.5-1.2B-MNN", "downloads": 10000},
            {"repo": "MNN/Qwen3-14B-MNN", "warnings": [{"code": "template_review_required"}]},
        ]
        self.assertEqual(mnn_catalog_sync.shortlist_candidates(candidates, 12, set()), [])

    def test_thinking_model_can_enter_queue(self) -> None:
        candidates = [{"repo": "MNN/Qwen3.5-4B-MNN", "warnings": [{"code": "thinking_enabled_by_default"}]}]
        self.assertEqual(mnn_catalog_sync.shortlist_candidates(candidates, 12, set()), candidates)

    def test_accepts_legacy_chatml_template(self) -> None:
        llm_config = {
            "prompt_template": "<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n%s<|im_end|>"
        }
        self.assertTrue(mnn_catalog_sync.has_chat_template(llm_config))

    def test_reports_missing_referenced_file(self) -> None:
        config = {"llm_model": "missing.mnn", "tokenizer_file": "tokenizer.txt"}
        llm_config = {"jinja": {"chat_template": "{{ messages }}"}}
        failures, _, _ = mnn_catalog_sync.static_compatibility(
            config, llm_config, runtime_files(), 4 * 1024**3
        )
        self.assertIn("referenced_file_missing", {item["code"] for item in failures})

    def test_shortlist_excludes_existing_and_specialized_models(self) -> None:
        def candidate(repo: str, downloads: int) -> dict:
            return {"repo": repo, "downloads": downloads, "lastUpdatedTime": 1}

        candidates = [
            candidate("MNN/Qwen3-0.6B-MNN", 1000),
            candidate("MNN/Qwen2.5-Coder-1.5B-Instruct-MNN", 900),
            candidate("MNN/Hunyuan-0.5B-Instruct-MNN", 100),
        ]
        shortlist = mnn_catalog_sync.shortlist_candidates(candidates, 12, mnn_catalog_sync.KNOWN_MNN_REPOS)
        self.assertEqual([item["repo"] for item in shortlist], ["MNN/Hunyuan-0.5B-Instruct-MNN"])

    def test_shortlist_excludes_model_already_published_online(self) -> None:
        candidates = [{"repo": "MNN/New-Model-MNN", "downloads": 100, "lastUpdatedTime": 1}]
        shortlist = mnn_catalog_sync.shortlist_candidates(candidates, 12, {"MNN/New-Model-MNN"})
        self.assertEqual(shortlist, [])


class CandidatePipelineTest(unittest.TestCase):
    def setUp(self) -> None:
        self.config = {"llm_model": "llm.mnn", "llm_weight": "llm.mnn.weight", "tokenizer_file": "tokenizer.txt"}
        self.configs = {
            "config.json": self.config,
            "llm_config.json": {"jinja": {"chat_template": "{{ messages }}"}},
        }
        self.files = [{"Path": item["relativePath"], "Size": item["sizeBytes"]} for item in runtime_files()]
        self.revision = "0123456789abcdef"
        catalog = mnn_catalog_sync.model_catalog
        files_patch = patch.object(catalog, "fetch_modelscope_files", return_value=(self.files, self.revision))
        self.fetch_files = files_patch.start()
        self.addCleanup(files_patch.stop)
        json_patch = patch.object(catalog, "fetch_repo_json", side_effect=lambda repo, rev, path: self.configs[path])
        self.fetch_json = json_patch.start()
        self.addCleanup(json_patch.stop)

    def add_generation_config(self, config: dict) -> None:
        self.files.append({"Path": "generation_config.json", "Size": 120})
        self.configs["generation_config.json"] = config

    def build(self, name: str = "Qwen3-2B-MNN") -> dict:
        return mnn_catalog_sync.build_candidate(metadata(name), 12 * 1024**3)

    def test_generation_config_fallback_uses_resolved_revision(self) -> None:
        self.add_generation_config({"temperature": 0.23, "top_p": 0.71, "top_k": 17, "do_sample": True})
        candidate = self.build()
        defaults = candidate["catalogItem"]["runtime"]["generationDefaults"]
        self.assertEqual((defaults["temperature"], defaults["topP"], defaults["topK"]), (0.23, 0.71, 17))
        self.assertEqual(candidate["failures"], [])
        self.assertEqual(candidate["catalogItem"]["source"]["revision"], self.revision)
        self.assertEqual({call.args[1] for call in self.fetch_json.call_args_list}, {self.revision})
        self.fetch_json.assert_any_call("MNN/Qwen3-2B-MNN", self.revision, "generation_config.json")

    def test_mnn_config_precedence_over_generation_config(self) -> None:
        self.config.update({"temperature": 0.4, "top_p": 0.8, "topP": 0.7, "penalty": 1.1})
        self.add_generation_config({"temperature": 0.2, "top_p": 0.5, "repetition_penalty": 1.2})
        defaults = self.build()["catalogItem"]["runtime"]["generationDefaults"]
        self.assertEqual((defaults["temperature"], defaults["topP"], defaults["repetitionPenalty"]), (0.4, 0.8, 1.1))

    def test_absent_generation_config_uses_defaults_without_fetch(self) -> None:
        defaults = self.build()["catalogItem"]["runtime"]["generationDefaults"]
        self.assertEqual(defaults["temperature"], 0.6)
        self.assertEqual(self.fetch_json.call_count, 2)

    def test_greedy_config_is_reported_as_error_not_candidate(self) -> None:
        self.add_generation_config({"do_sample": False})
        result = mnn_catalog_sync.scan_models([metadata("Qwen3-2B-MNN")], 12 * 1024**3, 1)
        self.assertEqual(result["candidates"], [])
        self.assertEqual(result["rejected"], [])
        self.assertEqual(len(result["errors"]), 1)
        self.assertIn("贪心解码", result["errors"][0]["message"])

    def test_malformed_generation_parameter_is_not_silently_defaulted(self) -> None:
        self.add_generation_config({"temperature": "bad"})
        with self.assertRaises(mnn_catalog_sync.model_catalog.CatalogError):
            self.build()

    def test_historical_failure_survives_as_reviewable_candidate(self) -> None:
        result = mnn_catalog_sync.scan_models([metadata("Hunyuan-0.5B-Instruct-MNN")], 12 * 1024**3, 1)
        self.assertEqual(result["rejected"], [])
        self.assertEqual(result["errors"], [])
        self.assertEqual(len(result["candidates"]), 1)
        candidate = result["candidates"][0]
        self.assertIn("historical_device_failure", {warning["code"] for warning in candidate["warnings"]})
        self.assertEqual(mnn_catalog_sync.shortlist_candidates([candidate], 12, set()), [])
        self.assertTrue(candidate["needsRetestReview"])

    def test_runtime_warning_does_not_pin_obsolete_version(self) -> None:
        warnings = self.build()["warnings"]
        message = next(item["message"] for item in warnings if item["code"] == "device_smoke_required")
        self.assertIn("当前 App", message)
        self.assertNotIn("3.6.0", message)


if __name__ == "__main__":
    unittest.main()
