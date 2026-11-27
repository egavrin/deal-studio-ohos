// The dealer agent harness (github.com/arkts-dev/dealer, crates/dealer-ffi) behind NAPI, for
// DealerBridge.ets. Dealer runs each turn on a thread of its own here, because its steps
// block; HTTP and tools are done by ArkTS: dealer's transport callback hands the request to JS
// (dealerSend), and JS answers through dealerHead / dealerChunk / dealerFinish; a tool call goes
// to the tool's JS callback, answered through dealerToolFinish. dealer.h allows both answers
// from any thread. Without the library (tools/build-dealer.sh) this builds as a stub whose
// dealerAvailable() is false.

#include <napi/native_api.h>
#include <hilog/log.h>

#include <pthread.h>

#include <cstdint>
#include <cstdio>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#ifndef DEALER_STUB
#include "dealer.h"
#endif

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0000
#define LOG_TAG "VERA-DEALER"

namespace {

// --- Calls back to JS from any thread -------------------------------------------------------

struct Post {
    std::function<void(napi_env)> run;
};

void CallJs(napi_env env, napi_value /*js*/, void * /*context*/, void *data)
{
    std::unique_ptr<Post> post(static_cast<Post *>(data));
    if (env != nullptr) {
        post->run(env);
    }
}

napi_threadsafe_function MakeChannel(napi_env env, const char *name)
{
    napi_value resource = nullptr;
    napi_create_string_utf8(env, name, NAPI_AUTO_LENGTH, &resource);
    napi_threadsafe_function channel = nullptr;
    napi_create_threadsafe_function(env, nullptr, nullptr, resource, 0, 1, nullptr, nullptr, nullptr, CallJs,
                                    &channel);
    return channel;
}

/**
 * Runs `body` on a detached thread of its own with a 2 MB stack, as Rust gives its own threads:
 * a dealer turn runs Rust code (JSON, schema checks, SQLite) on it, and musl's default thread
 * stack is far smaller. False when no thread could be made; `body` has not run then.
 */
bool Spawn(std::function<void()> body)
{
    constexpr size_t kStack = 2 * 1024 * 1024;
    auto *task = new std::function<void()>(std::move(body));  // NOLINT(cppcoreguidelines-owning-memory)
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, kStack);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t thread;
    int failed = pthread_create(&thread, &attr, [](void *data) -> void * {
        std::unique_ptr<std::function<void()>> task(static_cast<std::function<void()> *>(data));
        (*task)();
        return nullptr;
    }, task);
    pthread_attr_destroy(&attr);
    if (failed != 0) {
        delete task;  // NOLINT(cppcoreguidelines-owning-memory)
        return false;
    }
    return true;
}

bool PostTo(napi_threadsafe_function channel, std::function<void(napi_env)> run)
{
    auto *post = new Post{std::move(run)};  // NOLINT(cppcoreguidelines-owning-memory): owned by CallJs
    if (napi_call_threadsafe_function(channel, post, napi_tsfn_nonblocking) != napi_ok) {
        delete post;  // NOLINT(cppcoreguidelines-owning-memory)
        return false;
    }
    return true;
}

// --- Arguments ------------------------------------------------------------------------------

std::string StringArg(napi_env env, napi_value value)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return "";
    }
    std::string text(length, '\0');
    napi_get_value_string_utf8(env, value, text.data(), length + 1, &length);
    return text;
}

int64_t IntArg(napi_env env, napi_value value)
{
    int64_t number = 0;
    napi_get_value_int64(env, value, &number);
    return number;
}

napi_value String(napi_env env, const std::string &text)
{
    napi_value value = nullptr;
    napi_create_string_utf8(env, text.c_str(), text.size(), &value);
    return value;
}

napi_value Bool(napi_env env, bool flag)
{
    napi_value value = nullptr;
    napi_get_boolean(env, flag, &value);
    return value;
}

template <size_t N> size_t Args(napi_env env, napi_callback_info info, napi_value (&argv)[N])
{
    size_t argc = N;
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    return argc;
}

#ifndef DEALER_STUB

dealer_str Str(const std::string &text)
{
    return dealer_str{reinterpret_cast<const uint8_t *>(text.data()), text.size()};
}

std::string Take(dealer_error *error)
{
    std::string message = error != nullptr ? dealer_error_message(error) : "dealer failed";
    dealer_error_free(error);
    return message;
}

std::string Take(dealer_string text)
{
    std::string copy(reinterpret_cast<const char *>(text.ptr), text.len);
    dealer_string_free(text);
    return copy;
}

// --- The one instance this module runs -------------------------------------------------------

/** A run's generations by step, which dealerSteer may replace while it runs. */
struct Schedule {
    std::mutex mutex;
    std::vector<std::string> generations;
    /** The step generations[0] is for. */
    size_t first = 0;
    /** The step running now. */
    size_t step = 0;

    std::string For(size_t at)
    {
        std::lock_guard<std::mutex> lock(mutex);
        step = at;
        size_t index = at > first ? at - first : 0;
        return generations[index < generations.size() ? index : generations.size() - 1];
    }
};

struct Module {
    std::mutex mutex;
    dealer_instance *instance = nullptr;
    napi_threadsafe_function send = nullptr;
    napi_ref onSend = nullptr;
    std::map<int64_t, dealer_exchange *> exchanges;
    int64_t nextExchange = 1;
    std::map<int64_t, dealer_cancel *> cancels;
    std::map<int64_t, dealer_tool_call *> calls;
    int64_t nextCall = 1;
    std::map<int64_t, std::shared_ptr<Schedule>> schedules;
};


Module &TheModule()
{
    // Never freed: the instance and its threads live as long as the process.
    static auto *module = new Module();  // NOLINT(cppcoreguidelines-owning-memory)
    return *module;
}

void Send(void * /*user*/, dealer_str request, dealer_exchange *exchange)
{
    Module &module = TheModule();
    int64_t id = 0;
    {
        std::lock_guard<std::mutex> lock(module.mutex);
        id = module.nextExchange++;
        module.exchanges[id] = exchange;
    }
    std::string json(reinterpret_cast<const char *>(request.ptr), request.len);
    bool posted = PostTo(module.send, [id, json](napi_env env) {
        napi_value fn = nullptr;
        napi_value undefined = nullptr;
        napi_get_reference_value(env, TheModule().onSend, &fn);
        napi_get_undefined(env, &undefined);
        napi_value argv[2] = {nullptr, nullptr};
        napi_create_int64(env, id, &argv[0]);
        argv[1] = String(env, json);
        napi_call_function(env, undefined, fn, 2, argv, nullptr);
    });
    if (!posted) {
        std::lock_guard<std::mutex> lock(module.mutex);
        module.exchanges.erase(id);
        dealer_exchange_finish(exchange, DEALER_INVALID_STATE, Str("The app could not take the request"));
    }
}

dealer_exchange *Exchange(int64_t id, bool remove)
{
    Module &module = TheModule();
    std::lock_guard<std::mutex> lock(module.mutex);
    auto found = module.exchanges.find(id);
    if (found == module.exchanges.end()) {
        return nullptr;
    }
    dealer_exchange *exchange = found->second;
    if (remove) {
        module.exchanges.erase(found);
    }
    return exchange;
}

// dealerInit(dbPath, onSend): '' or why not. May be called again after a failure.
//
// The database starts empty in each process: Vera never reopens a session (each run's is
// deleted when it ends), so all a file left behind holds is the sessions of runs a crash cut
// short and provider definitions of keys and URLs no longer used.
napi_value Init(napi_env env, napi_callback_info info)
{
    napi_value argv[2] = {nullptr, nullptr};
    if (Args(env, info, argv) < 2) {
        return String(env, "dealerInit takes a database path and a send callback");
    }
    Module &module = TheModule();
    std::lock_guard<std::mutex> lock(module.mutex);
    if (module.instance != nullptr) {
        return String(env, "");
    }
    // Made once: a retry after a failed open reuses them.
    if (module.send == nullptr) {
        napi_create_reference(env, argv[1], 1, &module.onSend);
        module.send = MakeChannel(env, "dealerSend");
    }
    dealer_transport transport{sizeof(dealer_transport), nullptr, Send, nullptr};
    dealer_error *error = nullptr;
    std::string path = StringArg(env, argv[0]);
    for (const char *suffix : {"", "-wal", "-shm", ".dealer-lock"}) {
        std::remove((path + suffix).c_str());
    }
    if (dealer_instance_create(DEALER_ABI_VERSION, Str(path), &transport, &module.instance, &error) != DEALER_OK) {
        module.instance = nullptr;
        return String(env, Take(error));
    }
    OH_LOG_INFO(LOG_APP, "instance open, abi %{public}u", dealer_abi_version());
    return String(env, "");
}

// dealerRegisterProvider(json): '' or why not.
napi_value RegisterProvider(napi_env env, napi_callback_info info)
{
    napi_value argv[1] = {nullptr};
    Args(env, info, argv);
    dealer_error *error = nullptr;
    std::string json = StringArg(env, argv[0]);
    if (dealer_instance_register_provider(TheModule().instance, Str(json), &error) != DEALER_OK) {
        return String(env, Take(error));
    }
    return String(env, "");
}

// dealerHead(id, status, headersJson): '' or why not.
napi_value Head(napi_env env, napi_callback_info info)
{
    napi_value argv[3] = {nullptr, nullptr, nullptr};
    Args(env, info, argv);
    dealer_exchange *exchange = Exchange(IntArg(env, argv[0]), false);
    if (exchange == nullptr) {
        return String(env, "No such exchange");
    }
    dealer_error *error = nullptr;
    std::string headers = StringArg(env, argv[2]);
    auto status = static_cast<uint16_t>(IntArg(env, argv[1]));
    if (dealer_exchange_head(exchange, status, Str(headers), &error) != DEALER_OK) {
        return String(env, Take(error));
    }
    return String(env, "");
}

// dealerChunk(id, ArrayBuffer): '' or why not.
napi_value Chunk(napi_env env, napi_callback_info info)
{
    napi_value argv[2] = {nullptr, nullptr};
    Args(env, info, argv);
    dealer_exchange *exchange = Exchange(IntArg(env, argv[0]), false);
    void *data = nullptr;
    size_t length = 0;
    if (exchange == nullptr || napi_get_arraybuffer_info(env, argv[1], &data, &length) != napi_ok) {
        return String(env, "No such exchange, or the chunk is not an ArrayBuffer");
    }
    dealer_error *error = nullptr;
    if (dealer_exchange_chunk(exchange, dealer_str{static_cast<const uint8_t *>(data), length}, &error) !=
        DEALER_OK) {
        return String(env, Take(error));
    }
    return String(env, "");
}

// dealerFinish(id, ok, message): ends the exchange; dealer frees it.
napi_value Finish(napi_env env, napi_callback_info info)
{
    napi_value argv[3] = {nullptr, nullptr, nullptr};
    Args(env, info, argv);
    dealer_exchange *exchange = Exchange(IntArg(env, argv[0]), true);
    bool ok = false;
    napi_get_value_bool(env, argv[1], &ok);
    std::string message = StringArg(env, argv[2]);
    if (exchange != nullptr) {
        dealer_exchange_finish(exchange, ok ? DEALER_OK : DEALER_INVALID_STATE, Str(message));
    }
    return nullptr;
}

// dealerCancelled(id): whether dealer no longer wants the answer.
napi_value Cancelled(napi_env env, napi_callback_info info)
{
    napi_value argv[1] = {nullptr};
    Args(env, info, argv);
    dealer_exchange *exchange = Exchange(IntArg(env, argv[0]), false);
    return Bool(env, exchange == nullptr || dealer_exchange_is_cancelled(exchange));
}

// --- Tools: each registered with a JS callback, answered through dealerToolFinish -------------

/** A registered tool's JS callback; lives as long as the instance, which is never freed. */
struct ToolEntry {
    napi_ref onExecute = nullptr;
};

void Execute(void *user, dealer_str arguments, dealer_str context, dealer_tool_call *call)
{
    Module &module = TheModule();
    int64_t id = 0;
    {
        std::lock_guard<std::mutex> lock(module.mutex);
        id = module.nextCall++;
        module.calls[id] = call;
    }
    napi_ref callback = static_cast<ToolEntry *>(user)->onExecute;
    std::string args(reinterpret_cast<const char *>(arguments.ptr), arguments.len);
    std::string where(reinterpret_cast<const char *>(context.ptr), context.len);
    bool posted = PostTo(module.send, [callback, id, args, where](napi_env env) {
        napi_value fn = nullptr;
        napi_value undefined = nullptr;
        napi_get_reference_value(env, callback, &fn);
        napi_get_undefined(env, &undefined);
        napi_value argv[3] = {nullptr, String(env, args), String(env, where)};
        napi_create_int64(env, id, &argv[0]);
        napi_call_function(env, undefined, fn, 3, argv, nullptr);
    });
    if (!posted) {
        {
            std::lock_guard<std::mutex> lock(module.mutex);
            module.calls.erase(id);
        }
        dealer_tool_call_finish(call, DEALER_INVALID_STATE, Str("The app could not take the tool call"), nullptr);
    }
}

dealer_tool_call *Call(int64_t id, bool remove)
{
    Module &module = TheModule();
    std::lock_guard<std::mutex> lock(module.mutex);
    auto found = module.calls.find(id);
    if (found == module.calls.end()) {
        return nullptr;
    }
    dealer_tool_call *call = found->second;
    if (remove) {
        module.calls.erase(found);
    }
    return call;
}

// dealerRegisterTool(definitionJson, onExecute(callId, argumentsJson, contextJson)): '' or why not.
napi_value RegisterTool(napi_env env, napi_callback_info info)
{
    napi_value argv[2] = {nullptr, nullptr};
    if (Args(env, info, argv) < 2) {
        return String(env, "dealerRegisterTool takes a definition and a callback");
    }
    auto *entry = new ToolEntry();  // NOLINT(cppcoreguidelines-owning-memory): kept by the instance for good
    napi_create_reference(env, argv[1], 1, &entry->onExecute);
    dealer_tool tool{sizeof(dealer_tool), entry, Execute, nullptr};
    dealer_error *error = nullptr;
    std::string definition = StringArg(env, argv[0]);
    if (dealer_instance_register_tool(TheModule().instance, Str(definition), &tool, &error) != DEALER_OK) {
        napi_delete_reference(env, entry->onExecute);
        delete entry;  // NOLINT(cppcoreguidelines-owning-memory)
        return String(env, Take(error));
    }
    return String(env, "");
}

// dealerToolFinish(callId, ok, outcomeJson): '' or why not; dealer frees the call.
napi_value ToolFinish(napi_env env, napi_callback_info info)
{
    napi_value argv[3] = {nullptr, nullptr, nullptr};
    Args(env, info, argv);
    dealer_tool_call *call = Call(IntArg(env, argv[0]), true);
    if (call == nullptr) {
        return String(env, "No such tool call");
    }
    bool ok = false;
    napi_get_value_bool(env, argv[1], &ok);
    dealer_error *error = nullptr;
    std::string outcome = StringArg(env, argv[2]);
    if (dealer_tool_call_finish(call, ok ? DEALER_OK : DEALER_INVALID_STATE, Str(outcome), &error) != DEALER_OK) {
        return String(env, Take(error));
    }
    return String(env, "");
}

// dealerToolCancelled(callId): whether dealer no longer wants the answer.
napi_value ToolCancelled(napi_env env, napi_callback_info info)
{
    napi_value argv[1] = {nullptr};
    Args(env, info, argv);
    dealer_tool_call *call = Call(IntArg(env, argv[0]), false);
    return Bool(env, call == nullptr || dealer_tool_call_is_cancelled(call));
}

// --- Runs and decisions, each on a thread of its own -----------------------------------------

/** A promise and an optional event callback, settled from a worker thread. */
struct Pending {
    napi_deferred deferred = nullptr;
    napi_ref onEvent = nullptr;
    napi_threadsafe_function channel = nullptr;

    void Settle(bool ok, std::string text)
    {
        napi_threadsafe_function channel = this->channel;
        PostTo(channel, [this, ok, text](napi_env env) {
            napi_value value = String(env, text);
            if (ok) {
                napi_resolve_deferred(env, deferred, value);
            } else {
                napi_value error = nullptr;
                napi_create_error(env, nullptr, value, &error);
                napi_reject_deferred(env, deferred, error);
            }
            if (onEvent != nullptr) {
                napi_delete_reference(env, onEvent);
            }
            delete this;  // NOLINT(cppcoreguidelines-owning-memory): the last use of this run
        });
        napi_release_threadsafe_function(channel, napi_tsfn_release);
    }
};

Pending *MakePending(napi_env env, napi_value onEvent, napi_value *promise)
{
    auto *pending = new Pending();  // NOLINT(cppcoreguidelines-owning-memory): freed by Settle
    napi_create_promise(env, &pending->deferred, promise);
    if (onEvent != nullptr) {
        napi_create_reference(env, onEvent, 1, &pending->onEvent);
    }
    pending->channel = MakeChannel(env, "dealerRun");
    return pending;
}

void OnEvent(void *user, dealer_str event)
{
    auto *pending = static_cast<Pending *>(user);
    if (pending->onEvent == nullptr) {
        return;
    }
    std::string json(reinterpret_cast<const char *>(event.ptr), event.len);
    napi_ref callback = pending->onEvent;
    PostTo(pending->channel, [callback, json](napi_env env) {
        napi_value fn = nullptr;
        napi_value undefined = nullptr;
        napi_get_reference_value(env, callback, &fn);
        napi_get_undefined(env, &undefined);
        napi_value argv[1] = {String(env, json)};
        napi_call_function(env, undefined, fn, 1, argv, nullptr);
    });
}

std::vector<std::string> StringsArg(napi_env env, napi_value value)
{
    std::vector<std::string> strings;
    uint32_t length = 0;
    if (napi_get_array_length(env, value, &length) != napi_ok) {
        return strings;
    }
    for (uint32_t i = 0; i < length; i++) {
        napi_value item = nullptr;
        napi_get_element(env, value, i, &item);
        strings.push_back(StringArg(env, item));
    }
    return strings;
}

// A turn stops here even if the model keeps asking for tools; the last generation offers none.
constexpr size_t kMaxSteps = 16;

// dealerRun(runId, sessionId, generations, contextJson, inputJson, onEvent): Promise<resultJson>.
// A fresh session per run; its whole history stays in the database. Step i (from 0) runs with
// generations[i], the last one for every step after: a caller narrows the tools step by step.
// The result is the last step's {"finish_reason", "usage", "text"}.
napi_value Run(napi_env env, napi_callback_info info)
{
    napi_value argv[6] = {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
    Args(env, info, argv);
    int64_t runId = IntArg(env, argv[0]);
    std::string session = StringArg(env, argv[1]);
    std::vector<std::string> generations = StringsArg(env, argv[2]);
    std::string context = StringArg(env, argv[3]);
    std::string input = StringArg(env, argv[4]);
    napi_value promise = nullptr;
    Pending *pending = MakePending(env, argv[5], &promise);
    if (generations.empty()) {
        pending->Settle(false, "dealerRun takes at least one generation");
        return promise;
    }
    dealer_cancel *cancel = dealer_cancel_new();
    auto schedule = std::make_shared<Schedule>();
    schedule->generations = generations;
    {
        std::lock_guard<std::mutex> lock(TheModule().mutex);
        TheModule().cancels[runId] = cancel;
        TheModule().schedules[runId] = schedule;
    }
    bool spawned = Spawn([pending, cancel, runId, session, schedule, context, input]() {
        dealer_instance *instance = TheModule().instance;
        dealer_session *handle = nullptr;
        dealer_error *error = nullptr;
        dealer_observer observer{pending, OnEvent};
        dealer_string result{nullptr, 0};
        std::string current = schedule->For(0);
        int32_t status = dealer_session_create(instance, Str(session), Str(current), &handle, &error);
        if (status == DEALER_OK) {
            status = dealer_session_set_context(handle, Str(context), &error);
        }
        if (status == DEALER_OK) {
            status = dealer_session_start_turn(handle, Str(input), observer, &error);
        }
        bool done = false;
        for (size_t step = 0; status == DEALER_OK && !done; step++) {
            if (step >= kMaxSteps) {
                status = DEALER_INVALID_STATE;
                break;
            }
            std::string next = schedule->For(step);
            if (next != current) {
                current = next;
                status = dealer_session_set_generation(instance, handle, Str(current), &error);
                if (status != DEALER_OK) {
                    break;
                }
            }
            if (result.ptr != nullptr) {
                dealer_string_free(result);
                result = dealer_string{nullptr, 0};
            }
            status = dealer_session_step(handle, cancel, observer, &result, &done, &error);
        }
        dealer_session_free(handle);
        if (handle != nullptr) {
            // Nothing reopens it; kept, every run's whole context would pile up in the database.
            dealer_error *dropped = nullptr;
            if (dealer_session_delete(instance, Str(session), &dropped) != DEALER_OK) {
                OH_LOG_WARN(LOG_APP, "run %{public}s not deleted: %{public}s", session.c_str(), Take(dropped).c_str());
            }
        }
        {
            std::lock_guard<std::mutex> lock(TheModule().mutex);
            TheModule().cancels.erase(runId);
            TheModule().schedules.erase(runId);
        }
        dealer_cancel_free(cancel);
        if (status == DEALER_OK) {
            pending->Settle(true, Take(result));
        } else {
            if (result.ptr != nullptr) {
                dealer_string_free(result);
            }
            std::string message = "dealer status " + std::to_string(status) + ": " +
                                  (error != nullptr ? Take(error) : std::string("the model kept calling tools"));
            OH_LOG_WARN(LOG_APP, "run %{public}s failed: %{public}s", session.c_str(), message.c_str());
            pending->Settle(false, message);
        }
    });
    if (!spawned) {
        {
            std::lock_guard<std::mutex> lock(TheModule().mutex);
            TheModule().cancels.erase(runId);
            TheModule().schedules.erase(runId);
        }
        dealer_cancel_free(cancel);
        pending->Settle(false, "dealerRun could not start a thread");
    }
    return promise;
}

// dealerCancel(runId): stops a run or a decision; its promise rejects.
napi_value Cancel(napi_env env, napi_callback_info info)
{
    napi_value argv[1] = {nullptr};
    Args(env, info, argv);
    int64_t runId = IntArg(env, argv[0]);
    std::lock_guard<std::mutex> lock(TheModule().mutex);
    auto found = TheModule().cancels.find(runId);
    if (found != TheModule().cancels.end()) {
        dealer_cancel_trigger(found->second);
    }
    return nullptr;
}

// dealerSteer(runId, generations): from the run's next step on, step next+i runs with
// generations[i], the last one for every step after.
napi_value Steer(napi_env env, napi_callback_info info)
{
    napi_value argv[2] = {nullptr, nullptr};
    Args(env, info, argv);
    int64_t runId = IntArg(env, argv[0]);
    std::vector<std::string> generations = StringsArg(env, argv[1]);
    std::shared_ptr<Schedule> schedule;
    {
        std::lock_guard<std::mutex> lock(TheModule().mutex);
        auto found = TheModule().schedules.find(runId);
        if (found != TheModule().schedules.end()) {
            schedule = found->second;
        }
    }
    if (schedule != nullptr && !generations.empty()) {
        std::lock_guard<std::mutex> lock(schedule->mutex);
        schedule->generations = generations;
        schedule->first = schedule->step + 1;
    }
    return nullptr;
}

// dealerDecide(runId, endpoint, key, requestJson): Promise<answerJson>. dealerCancel(runId) stops it.
napi_value Decide(napi_env env, napi_callback_info info)
{
    napi_value argv[4] = {nullptr, nullptr, nullptr, nullptr};
    Args(env, info, argv);
    int64_t runId = IntArg(env, argv[0]);
    std::string endpoint = StringArg(env, argv[1]);
    std::string key = StringArg(env, argv[2]);
    std::string request = StringArg(env, argv[3]);
    napi_value promise = nullptr;
    Pending *pending = MakePending(env, nullptr, &promise);
    dealer_cancel *cancel = dealer_cancel_new();
    {
        std::lock_guard<std::mutex> lock(TheModule().mutex);
        TheModule().cancels[runId] = cancel;
    }
    auto forget = [runId, cancel]() {
        {
            std::lock_guard<std::mutex> lock(TheModule().mutex);
            TheModule().cancels.erase(runId);
        }
        dealer_cancel_free(cancel);
    };
    bool spawned = Spawn([pending, endpoint, key, request, cancel, forget]() {
        dealer_error *error = nullptr;
        dealer_string answer{nullptr, 0};
        int32_t status = dealer_decide(TheModule().instance, Str(endpoint), Str(key), Str(request), cancel,
                                       &answer, &error);
        forget();
        if (status == DEALER_OK) {
            pending->Settle(true, Take(answer));
        } else {
            std::string message = "dealer status " + std::to_string(status) + ": " + Take(error);
            OH_LOG_WARN(LOG_APP, "decide failed: %{public}s", message.c_str());
            pending->Settle(false, message);
        }
    });
    if (!spawned) {
        forget();
        pending->Settle(false, "dealerDecide could not start a thread");
    }
    return promise;
}

napi_value Available(napi_env env, napi_callback_info /*info*/)
{
    return Bool(env, true);
}

#else  // DEALER_STUB

napi_value Unavailable(napi_env env, napi_callback_info /*info*/)
{
    return String(env, "This build has no dealer library (tools/build-dealer.sh)");
}

napi_value Available(napi_env env, napi_callback_info /*info*/)
{
    return Bool(env, false);
}

#endif

napi_value Register(napi_env env, napi_value exports)
{
#ifndef DEALER_STUB
    napi_property_descriptor desc[] = {
        {"dealerAvailable", nullptr, Available, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerInit", nullptr, Init, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerRegisterProvider", nullptr, RegisterProvider, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerHead", nullptr, Head, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerChunk", nullptr, Chunk, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerFinish", nullptr, Finish, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerCancelled", nullptr, Cancelled, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerRun", nullptr, Run, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerCancel", nullptr, Cancel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerDecide", nullptr, Decide, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerRegisterTool", nullptr, RegisterTool, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerToolFinish", nullptr, ToolFinish, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerToolCancelled", nullptr, ToolCancelled, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerSteer", nullptr, Steer, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
#else
    napi_property_descriptor desc[] = {
        {"dealerAvailable", nullptr, Available, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerInit", nullptr, Unavailable, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
#endif
    if (napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc) != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "cannot define the dealer functions");
    }
    return exports;
}

}  // namespace

EXTERN_C_START
// napi_module_register takes a non-const pointer and keeps it.
static napi_module g_module = {  // NOLINT(cppcoreguidelines-avoid-non-const-global-variables)
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Register,
    .nm_modname = "dealer",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

__attribute__((constructor)) void RegisterDealer(void)
{
    napi_module_register(&g_module);
}
EXTERN_C_END
