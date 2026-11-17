# H2O-Lightning decision wrapper

[简体中文](README.md) | [English](README_EN.md)

Runs H2O-Lightning-4B through MNN LLM Runtime. Provides loading, text and single-image decisions, candidate probabilities, and model release. Follows the official v1.4.2 causal path, including its prompt, 255 candidate labels, and classification temperatures from `serve_config.json`.

## Build

Add `h2o_decision.cpp` and `h2o_protocol.cpp` to the caller's native target. Add this directory and the project's `third_party/mnn/include` to the include paths, link `libMNN.so`, and enable C++17. `h2o_contract.h` contains the prompt and label contract for this model version.

Pass the path to `config.json` in a complete MNN model directory. The directory must contain the backbone, output head, embeddings, tokenizer, and runtime configuration. Image requests also require the visual model. Loading verifies every candidate label token ID against the official tokenizer.

The wrapper supports full-vocabulary packages and packages with the 255 candidate-label outputs. Candidate-output packages set `"decision_output": "h2o-labels-v1"` in `config.json` and follow the `labelTokens` order in `h2o_contract.h`. The wrapper validates the output count and reads the corresponding logits. Full-vocabulary packages use token-ID indexing.

The wrapper uses CPU inference with four threads by default, `precision=normal`, `memory=low`, and `dynamic_option=2`, matching the INT8 validation configuration. Perform loading and inference on background worker threads.

### Compact decision output head

`compact_model.py` converts this project's original INT8 package to candidate outputs, reducing the memory needed to load the output head. It verifies source checksums, extracts the original FP16 rows for the 255 official labels, and removes the full output head from the end of the weight file. It requires Python 3.11 or later, a C++ compiler, and the matching MNN source tree.

```sh
python scripts/h2o/compact_model.py --source /path/to/original-model \
    --output /path/to/compact-model --mnn-source /path/to/MNN
```

The output directory must be new. It contains the model, runtime configuration, conversion metadata, and SHA-256 checksums. Candidate-output packages require this version of the decision wrapper.

## Text decisions

```cpp
#include "h2o_decision.h"

H2o::DecisionModel model;
model.load(modelDirectory + "/config.json");

H2o::Question question;
question.type = H2o::QuestionType::Choice;
question.state = "A customer has paid, but the order still shows payment pending.";
question.instruction = "Which team should handle this issue?";
question.options = {
    {"payment", "Payments and orders"},
    {"shipping", "Shipping and delivery"}
};
auto result = model.decide(question);
const auto& selectedName = result.options[result.selectedIndex].name;
model.release();
```

Options retain the caller's order. Choice requires unique names and descriptions. Noul uses `true` followed by `false`, or an empty options vector for the official default descriptions. Score uses consecutive names starting at `0`, with a description for each level.

## Image decisions

```cpp
H2o::Image image;
image.width = width;
image.height = height;
image.rgb = rgbPixels;
auto result = model.decide(question, &image);
```

Supply packed RGB bytes, three bytes per pixel, without row padding. The wrapper converts channels for MNN, while the model's visual configuration controls resizing. Image questions use the official temperature of `1.0`. Text arguments must not contain MNN media-path markers.

## Results and lifecycle

- `probabilities` follows `options` order and sums to one. For Noul, the first value is the affirmative probability.
- `selectedIndex` identifies the most probable option. Ties select the first option.
- For Score, `score` is the probability-weighted expected level and can be fractional.
- For Choice, `confidence` uses the official normalized maximum probability, ranging from zero for a uniform distribution to one for a point mass. For Score, it is the highest level probability. For Noul, use the affirmative probability.
- `inputTokens` is the final input token count. `preprocessingMs` includes tokenization and visual encoding. `forwardMs` covers the language-model forward pass and candidate-logit readout.

Every question starts with a reset context. The default full-input limit is 40,960 tokens. Lower it with the third argument to `load`. Over-limit requests throw an exception so the caller can shorten the input and retry.

Loading, decisions, and release are serialized by an instance mutex. Release waits for a running decision. Release before loading again. Repeated release is safe, and a failed load leaves the instance unloaded. Destruction automatically frees the model. Join all worker threads using an instance before destroying it.

## Protocol checks

The compact-output checks cover weight bytes, zero bias, output shapes, and invalid inputs.

```sh
python scripts/h2o/tests/test_compact_output.py --mnn-source /path/to/MNN
```

These checks require a C++17 compiler and run without model weights.

```sh
g++ -std=c++17 -Wall -Wextra -Werror -I scripts/h2o \
    scripts/h2o/h2o_protocol.cpp scripts/h2o/tests/protocol_test.cpp \
    -o h2o_protocol_test
./h2o_protocol_test
```

The model and serving contract come from the [official H2O model repository](https://huggingface.co/h2oai/h2o-lightning-4b/tree/659fc412de8486dbc2477b0d1cb4121e97e72471).
