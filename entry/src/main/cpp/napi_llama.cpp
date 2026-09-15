/**
 * NAPI wrapper for llama.cpp — exposes llamaInit, llamaGenerate, llamaStop, llamaFree
 * to ArkTS as the 'llama' native module.
 *
 * Build: place llama.cpp source in entry/src/main/cpp/llama.cpp/ (git clone)
 * The CMakeLists.txt handles linking.
 *
 * When LLAMA_STUB is defined, all functions return failure — allows building
 * the app without llama.cpp for UI development.
 */

#include <cstdlib>
#include <cstring>
#include <string>
#include <atomic>
#include <napi/native_api.h>

#ifndef LLAMA_STUB
#include "llama.h"
#include "common.h"
#endif

static std::atomic<bool> g_stop_flag{false};

#ifndef LLAMA_STUB
static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;
static llama_sampler* g_sampler = nullptr;

struct JsonValue {
    std::string str;
    double num = 0;
    bool boolean = false;
    enum Type { String, Number, Bool } type;
};

static std::string json_string(napi_env env, napi_value obj, const char* key) {
    napi_value val;
    if (napi_get_named_property(env, obj, key, &val) != napi_ok) return "";
    size_t len = 0;
    napi_get_value_string_utf8(env, val, nullptr, 0, &len);
    std::string result(len, '\0');
    napi_get_value_string_utf8(env, val, result.data(), len + 1, &len);
    return result;
}

static double json_double(napi_env env, napi_value obj, const char* key, double def) {
    napi_value val;
    if (napi_get_named_property(env, obj, key, &val) != napi_ok) return def;
    double result = def;
    napi_get_value_double(env, val, &result);
    return result;
}

static int json_int(napi_env env, napi_value obj, const char* key, int def) {
    return static_cast<int>(json_double(env, obj, key, def));
}
#endif

// llamaInit(configJson: string): boolean
static napi_value LlamaInit(napi_env env, napi_callback_info info) {
    napi_value result;
#ifdef LLAMA_STUB
    napi_get_boolean(env, false, &result);
    return result;
#else
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // Parse config JSON string
    size_t json_len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &json_len);
    std::string config_json(json_len, '\0');
    napi_get_value_string_utf8(env, args[0], config_json.data(), json_len + 1, &json_len);

    // Parse JSON with napi (convert string to object)
    napi_value global, json_obj, parse_fn, config_val;
    napi_get_global(env, &global);
    napi_get_named_property(env, global, "JSON", &json_obj);
    napi_get_named_property(env, json_obj, "parse", &parse_fn);
    napi_value json_str;
    napi_create_string_utf8(env, config_json.c_str(), config_json.size(), &json_str);
    napi_call_function(env, json_obj, parse_fn, 1, &json_str, &config_val);

    std::string model_path = json_string(env, config_val, "model_path");
    int n_ctx = json_int(env, config_val, "n_ctx", 4096);
    int n_threads = json_int(env, config_val, "n_threads", 4);
    int n_gpu_layers = json_int(env, config_val, "n_gpu_layers", 0);

    if (g_model) { llama_model_free(g_model); g_model = nullptr; }
    if (g_ctx) { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_sampler) { llama_sampler_free(g_sampler); g_sampler = nullptr; }

    auto mparams = llama_model_default_params();
    mparams.n_gpu_layers = n_gpu_layers;
    g_model = llama_model_load_from_file(model_path.c_str(), mparams);
    if (!g_model) {
        napi_get_boolean(env, false, &result);
        return result;
    }

    auto cparams = llama_context_default_params();
    cparams.n_ctx = n_ctx;
    cparams.n_threads = n_threads;
    cparams.n_threads_batch = n_threads;
    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) {
        llama_model_free(g_model); g_model = nullptr;
        napi_get_boolean(env, false, &result);
        return result;
    }

    g_sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(0.95f, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(0.2f));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(42));

    napi_get_boolean(env, true, &result);
    return result;
#endif
}

// llamaGenerate(paramsJson: string, callback: (token: string) => void): {text, inputTokens, outputTokens}
static napi_value LlamaGenerate(napi_env env, napi_callback_info info) {
#ifdef LLAMA_STUB
    napi_value result_obj;
    napi_create_object(env, &result_obj);
    napi_value empty_str, zero_val;
    napi_create_string_utf8(env, "", 0, &empty_str);
    napi_create_int32(env, 0, &zero_val);
    napi_set_named_property(env, result_obj, "text", empty_str);
    napi_set_named_property(env, result_obj, "inputTokens", zero_val);
    napi_set_named_property(env, result_obj, "outputTokens", zero_val);
    return result_obj;
#else
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // Parse params
    size_t json_len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &json_len);
    std::string params_json(json_len, '\0');
    napi_get_value_string_utf8(env, args[0], params_json.data(), json_len + 1, &json_len);

    napi_value global, json_obj, parse_fn, params_val;
    napi_get_global(env, &global);
    napi_get_named_property(env, global, "JSON", &json_obj);
    napi_get_named_property(env, json_obj, "parse", &parse_fn);
    napi_value jstr;
    napi_create_string_utf8(env, params_json.c_str(), params_json.size(), &jstr);
    napi_call_function(env, json_obj, parse_fn, 1, &jstr, &params_val);

    std::string prompt = json_string(env, params_val, "prompt");
    std::string grammar_str = json_string(env, params_val, "grammar");
    int max_tokens = json_int(env, params_val, "max_tokens", 2048);

    napi_value callback = args[1];

    if (!g_model || !g_ctx) {
        napi_value result_obj;
        napi_create_object(env, &result_obj);
        napi_value empty_str, zero_val;
        napi_create_string_utf8(env, "", 0, &empty_str);
        napi_create_int32(env, 0, &zero_val);
        napi_set_named_property(env, result_obj, "text", empty_str);
        napi_set_named_property(env, result_obj, "inputTokens", zero_val);
        napi_set_named_property(env, result_obj, "outputTokens", zero_val);
        return result_obj;
    }

    // Tokenize prompt
    auto vocab = llama_model_get_vocab(g_model);
    int n_prompt = llama_tokenize(vocab, prompt.c_str(), prompt.size(), nullptr, 0, true, true);
    std::vector<llama_token> tokens(n_prompt);
    llama_tokenize(vocab, prompt.c_str(), prompt.size(), tokens.data(), tokens.size(), true, true);

    // Set up grammar if provided
    auto* grammar = grammar_str.empty() ? nullptr :
        llama_grammar_init_impl(vocab, grammar_str.c_str(), "root");

    // Decode prompt
    llama_kv_cache_clear(g_ctx);
    llama_batch batch = llama_batch_get_one(tokens.data(), tokens.size());
    llama_decode(g_ctx, batch);

    // Generate
    g_stop_flag.store(false);
    std::string full_output;
    int output_token_count = 0;

    for (int i = 0; i < max_tokens && !g_stop_flag.load(); i++) {
        llama_token new_token;
        if (grammar) {
            llama_sampler_accept(g_sampler, new_token); // apply grammar constraint
        }
        new_token = llama_sampler_sample(g_sampler, g_ctx, -1);

        if (llama_token_is_eog(vocab, new_token)) break;

        char buf[256];
        int n = llama_token_to_piece(vocab, new_token, buf, sizeof(buf), 0, true);
        if (n > 0) {
            std::string piece(buf, n);
            full_output += piece;
            output_token_count++;

            // Stream token to callback
            napi_value token_str, cb_result;
            napi_create_string_utf8(env, piece.c_str(), piece.size(), &token_str);
            napi_value undef;
            napi_get_undefined(env, &undef);
            napi_call_function(env, undef, callback, 1, &token_str, &cb_result);
        }

        // Prepare next decode
        llama_batch next_batch = llama_batch_get_one(&new_token, 1);
        llama_decode(g_ctx, next_batch);
    }

    if (grammar) llama_grammar_free_impl(grammar);

    napi_value result_obj;
    napi_create_object(env, &result_obj);
    napi_value text_val;
    napi_create_string_utf8(env, full_output.c_str(), full_output.size(), &text_val);
    napi_set_named_property(env, result_obj, "text", text_val);
    napi_value input_tokens_val;
    napi_create_int32(env, n_prompt, &input_tokens_val);
    napi_set_named_property(env, result_obj, "inputTokens", input_tokens_val);
    napi_value output_tokens_val;
    napi_create_int32(env, output_token_count, &output_tokens_val);
    napi_set_named_property(env, result_obj, "outputTokens", output_tokens_val);
    return result_obj;
#endif
}

// llamaStop(): void
static napi_value LlamaStop(napi_env env, napi_callback_info info) {
    g_stop_flag.store(true);
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

// llamaFree(): void
static napi_value LlamaFree(napi_env env, napi_callback_info info) {
#ifndef LLAMA_STUB
    if (g_sampler) { llama_sampler_free(g_sampler); g_sampler = nullptr; }
    if (g_ctx) { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model) { llama_model_free(g_model); g_model = nullptr; }
#endif
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

// Module registration
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"llamaInit", nullptr, LlamaInit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"llamaGenerate", nullptr, LlamaGenerate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"llamaStop", nullptr, LlamaStop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"llamaFree", nullptr, LlamaFree, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

EXTERN_C_START
static napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "llama",
    .nm_priv = nullptr,
    .reserved = {0},
};

__attribute__((constructor)) void RegisterModule(void) {
    napi_module_register(&g_module);
}
EXTERN_C_END
