// Optional local Jev runner (Rust/Candle). Always packaged; without an archive it
// reports unavailable. Two callers share it: the local selector (status,
// experimentalDecisions) and the composition decision model (predict,
// diagnosticScores), plus the NPU bucket registration and ABI probe.
#include <napi/native_api.h>
#include <atomic>
#include <memory>
#include <string>
#include <vector>
#ifdef VERA_LOCAL_JEV
#include "local_jev.h"
#endif

namespace {
constexpr size_t MAX_INPUT = 262144;
std::atomic<bool> busy{false};

enum class Kind { Status, Experimental, Predict, Diagnostic };

struct Work {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    Kind kind = Kind::Status;
    std::string input;
    std::string output;
    std::string error;
};

void Execute(napi_env, void *data)
{
    auto &job = *static_cast<Work *>(data);
    try {
#ifdef VERA_LOCAL_JEV
        if (local_jev_abi() != 1) { job.error = "Local Jev ABI mismatch"; return; }
        char *reply = nullptr;
        switch (job.kind) {
            case Kind::Status:
                reply = local_jev_status();
                break;
            case Kind::Experimental:
                reply = local_jev_experimental_decisions(
                    reinterpret_cast<const uint8_t *>(job.input.data()), job.input.size());
                break;
            case Kind::Predict:
                reply = local_jev_predict(
                    reinterpret_cast<const uint8_t *>(job.input.data()), job.input.size());
                break;
            case Kind::Diagnostic:
                reply = local_jev_diagnostic_scores(
                    reinterpret_cast<const uint8_t *>(job.input.data()), job.input.size());
                break;
        }
        if (!reply) { job.error = "Local Jev returned no reply"; return; }
        std::unique_ptr<char, decltype(&local_jev_free)> owned(reply, local_jev_free);
        job.output = owned.get();
#else
        job.output = job.kind == Kind::Status
            ? "{\"ready\":false,\"reason\":\"archive_not_linked\"}"
            : "{\"answers\":{},\"local\":{\"status\":\"uncertain\",\"reason\":\"archive_not_linked\"}}";
#endif
    } catch (...) { job.error = "Local Jev native failure"; }
}

void Complete(napi_env env, napi_status status, void *data)
{
    std::unique_ptr<Work> job(static_cast<Work *>(data));
    if (status != napi_ok) { job->error = "Local Jev async work cancelled"; }
    // Release before resolving: ArkTS may resume the awaiting caller inline and
    // immediately issue the next selector request from the promise continuation.
    busy.store(false);
    napi_value value = nullptr;
    if (job->error.empty() && napi_create_string_utf8(env, job->output.c_str(), job->output.size(), &value) == napi_ok) {
        napi_resolve_deferred(env, job->deferred, value);
    } else {
        napi_value message = nullptr;
        napi_create_string_utf8(env, job->error.empty() ? "Local Jev reply failed" : job->error.c_str(), NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &value);
        napi_reject_deferred(env, job->deferred, value);
    }
    napi_delete_async_work(env, job->work);
}

napi_value Queue(napi_env env, napi_callback_info info, Kind kind)
{
    auto job = std::make_unique<Work>();
    job->kind = kind;
    if (kind != Kind::Status) {
        size_t argc = 1, length = 0;
        napi_value arg = nullptr;
        if (napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr) != napi_ok || argc != 1 ||
            napi_get_value_string_utf8(env, arg, nullptr, 0, &length) != napi_ok || length > MAX_INPUT) {
            napi_throw_error(env, nullptr, "Local Jev expects UTF-8 JSON up to 262144 bytes");
            return nullptr;
        }
        std::vector<char> bytes(length + 1);
        if (napi_get_value_string_utf8(env, arg, bytes.data(), bytes.size(), &length) != napi_ok) {
            napi_throw_error(env, nullptr, "Local Jev input copy failed"); return nullptr;
        }
        job->input.assign(bytes.data(), length);
    }
    // Bound work even across multiple ArkTS environments. Rust also serializes its singleton.
    if (busy.exchange(true)) { napi_throw_error(env, nullptr, "Local Jev busy"); return nullptr; }
    napi_value promise = nullptr, name = nullptr;
    if (napi_create_promise(env, &job->deferred, &promise) != napi_ok ||
        napi_create_string_utf8(env, "localjev", NAPI_AUTO_LENGTH, &name) != napi_ok ||
        napi_create_async_work(env, nullptr, name, Execute, Complete, job.get(), &job->work) != napi_ok ||
        napi_queue_async_work(env, job->work) != napi_ok) {
        if (job->work) { napi_delete_async_work(env, job->work); }
        busy.store(false);
        napi_throw_error(env, nullptr, "Local Jev could not queue work"); return nullptr;
    }
    job.release();
    return promise;
}

napi_value Status(napi_env env, napi_callback_info info) { return Queue(env, info, Kind::Status); }
napi_value Experimental(napi_env env, napi_callback_info info) { return Queue(env, info, Kind::Experimental); }
napi_value Predict(napi_env env, napi_callback_info info) { return Queue(env, info, Kind::Predict); }
napi_value Diagnostic(napi_env env, napi_callback_info info) { return Queue(env, info, Kind::Diagnostic); }

napi_value Abi(napi_env env, napi_callback_info info)
{
    (void)info;
    uint32_t v = 0;
#ifdef VERA_LOCAL_JEV
    v = local_jev_abi();
#endif
    napi_value out;
    napi_create_uint32(env, v, &out);
    return out;
}

napi_value NpuGraph(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_error(env, nullptr, "npuGraph requires a path");
        return nullptr;
    }
    char path[512];
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], path, sizeof(path) - 1, &len);
    path[len] = '\0';
    int32_t batch = 8;
    int32_t seq = 256;
    if (argc >= 3) {
        napi_get_value_int32(env, args[1], &batch);
        napi_get_value_int32(env, args[2], &seq);
    }
    bool ok = true;
#ifdef VERA_LOCAL_JEV
    ok = local_jev_npu_graph(reinterpret_cast<const uint8_t *>(path), len,
                             static_cast<size_t>(batch), static_cast<size_t>(seq)) != 0;
#endif
    napi_value out;
    napi_get_boolean(env, ok, &out);
    return out;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        {"status", nullptr, Status, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"experimentalDecisions", nullptr, Experimental, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"predict", nullptr, Predict, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"diagnosticScores", nullptr, Diagnostic, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"abi", nullptr, Abi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"npuGraph", nullptr, NpuGraph, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}
}

static napi_module module = {
    .nm_version = 1, .nm_flags = 0, .nm_filename = nullptr,
    .nm_register_func = Init, .nm_modname = "localjev", .nm_priv = nullptr, .reserved = {nullptr},
};
extern "C" __attribute__((constructor)) void RegisterLocalJev() { napi_module_register(&module); }
