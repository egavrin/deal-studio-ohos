/**
 * MindSpore Lite C-NDK probe for the Kirin NPU (NNRT) — the decisive NNRT test that
 * the ArkTS @ohos.ai.mindSporeLite API could not do (its getInputs() is undefined for
 * NNRT models). Loads the converted decision model (jev_fill.ms) with an NNRT
 * accelerator device, sets the inputs, predicts, and logs under VERA-MSNNRT. Exposed to
 * ArkTS as `msnnrt.run(path): Promise<string>` returning
 * {ok,status,dev,latencyMs,logits,note}.
 */
#include <cstring>
#include <cstdio>
#include <string>
#include <chrono>
#include <dlfcn.h>
// Vendored HiAI Foundation interface headers (Apache-2.0, see hiai/LICENSE).
#include "hiai/c/hiai_model_builder.h"
#include "hiai/c/hiai_model_manager.h"
#include "hiai/c/hiai_built_model.h"
#include "hiai/c/hiai_nd_tensor_buffer.h"
#include "hiai/c/hiai_nd_tensor_desc.h"
#include "hiai/c/hiai_version.h"
#include "hiai/interface/attr_def.h"
#include "hiai/interface/attr_list_def.h"
#include "hiai/interface/attr_map_def.h"
#include "hiai/interface/graph_def.h"
#include "hiai/interface/model_def.h"
#include "hiai/interface/op_def.h"
#include "hiai/interface/shape_def.h"
#include "hiai/interface/tensor_def.h"
#include "hiai/interface/tensor_desc_def.h"
#include <string>
#include <vector>
#include <napi/native_api.h>
#include <hilog/log.h>
#include <mindspore/context.h>
#include <mindspore/model.h>
#include <mindspore/tensor.h>
#include <mindspore/status.h>
#include <mindspore/types.h>

#define TAG "VERA-MSNNRT"
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0, TAG, __VA_ARGS__)

struct Job {
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  std::string path;
  std::string result;
};

static std::string run_nnrt(const std::string& path) {
  auto t0 = std::chrono::steady_clock::now();
  size_t ndesc = 0;
  NNRTDeviceDesc* descs = OH_AI_GetAllNNRTDeviceDescs(&ndesc);
  std::string devname = "?";
  size_t devid = 0;
  bool haveAccel = false;
  for (size_t i = 0; i < ndesc; i++) {
    NNRTDeviceDesc* d = OH_AI_GetElementOfNNRTDeviceDescs(descs, i);
    OH_AI_NNRTDeviceType ty = OH_AI_GetTypeFromNNRTDeviceDesc(d);
    LOGI("nnrt desc %zu type=%d name=%s", i, (int)ty, OH_AI_GetNameFromNNRTDeviceDesc(d));
    if (ty == OH_AI_NNRTDEVICE_ACCELERATOR && !haveAccel) {
      devname = OH_AI_GetNameFromNNRTDeviceDesc(d);
      devid = OH_AI_GetDeviceIdFromNNRTDeviceDesc(d);
      haveAccel = true;
    }
  }
  OH_AI_ContextHandle ctx = OH_AI_ContextCreate();
  OH_AI_DeviceInfoHandle dev = nullptr;
  if (haveAccel) {
    dev = OH_AI_CreateNNRTDeviceInfoByType(OH_AI_NNRTDEVICE_ACCELERATOR);
    if (devid != 0) { OH_AI_DeviceInfoSetDeviceId(dev, devid); }
  } else {
    dev = OH_AI_DeviceInfoCreate(OH_AI_DEVICETYPE_NNRT);
  }
  OH_AI_ContextAddDeviceInfo(ctx, dev);

  OH_AI_ModelHandle model = OH_AI_ModelCreate();
  OH_AI_Status st = OH_AI_ModelBuildFromFile(model, path.c_str(), OH_AI_MODELTYPE_MINDIR, ctx);
  double build_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  char buf[320];
  snprintf(buf, sizeof buf, "build status=%d dev=%s(%zu) buildMs=%.0f", (int)st, devname.c_str(), devid, build_ms);
  LOGI("%s", buf);

  int ok = 0;
  int cpuBuild = -1;
  std::string logits, note;
  if (st == OH_AI_STATUS_SUCCESS) {
    OH_AI_TensorHandleArray in = OH_AI_ModelGetInputs(model);
    snprintf(buf, sizeof buf, "inputs handle_num=%zu", in.handle_num);
    LOGI("%s", buf);
    if (in.handle_num > 0) {
      for (size_t i = 0; i < in.handle_num; i++) {
        OH_AI_TensorHandle t = in.handle_list[i];
        size_t sz = OH_AI_TensorGetDataSize(t);
        void* p = OH_AI_TensorGetMutableData(t);
        if (p != nullptr && sz > 0) { memset(p, 0, sz); }
        size_t nshape = 0;
        const int64_t* shp = OH_AI_TensorGetShape(t, &nshape);
        std::string s;
        for (size_t k = 0; k < nshape; k++) { s += std::to_string(shp[k]); if (k + 1 < nshape) s += "x"; }
        LOGI("  in %zu name=%s dtype=%d shape=%s dataSize=%zu", i, OH_AI_TensorGetName(t),
             (int)OH_AI_TensorGetDataType(t), s.c_str(), sz);
      }
      auto t1 = std::chrono::steady_clock::now();
      OH_AI_TensorHandleArray out;
      memset(&out, 0, sizeof out);
      OH_AI_Status pst = OH_AI_ModelPredict(model, in, &out, nullptr, nullptr);
      double pred_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t1).count();
      snprintf(buf, sizeof buf, "predict status=%d out handle_num=%zu predMs=%.1f", (int)pst, out.handle_num, pred_ms);
      LOGI("%s", buf);
      if (pst == OH_AI_STATUS_SUCCESS && out.handle_num > 0) {
        OH_AI_TensorHandle o = out.handle_list[0];
        int64_t n = OH_AI_TensorGetElementNum(o);
        int dt = (int)OH_AI_TensorGetDataType(o);
        if (dt == OH_AI_DATATYPE_NUMBERTYPE_FLOAT32) {
          const float* d = (const float*)OH_AI_TensorGetData(o);
          int show = n < 8 ? (int)n : 8;
          for (int k = 0; k < show; k++) { char b[32]; snprintf(b, sizeof b, "%.4f ", d[k]); logits += b; }
          ok = 1;
          LOGI("output logits n=%lld head=%s", (long long)n, logits.c_str());
        } else {
          note = "output not f32, dtype=" + std::to_string(dt);
          LOGI("%s", note.c_str());
        }
      } else if (pst != OH_AI_STATUS_SUCCESS) {
        note = "predict_failed";
      }
    } else {
      note = "no_inputs";
    }
  } else {
    note = "build_failed";
    // Control: the same file with a CPU device context. Building on CPU but
    // not on the accelerator separates "the NPU rejects this graph" from "the
    // file cannot be read by this runtime at all".
    OH_AI_ContextHandle cpuCtx = OH_AI_ContextCreate();
    OH_AI_DeviceInfoHandle cpu = OH_AI_DeviceInfoCreate(OH_AI_DEVICETYPE_CPU);
    OH_AI_ContextAddDeviceInfo(cpuCtx, cpu);
    OH_AI_ModelHandle cpuModel = OH_AI_ModelCreate();
    OH_AI_Status cst = OH_AI_ModelBuildFromFile(cpuModel, path.c_str(), OH_AI_MODELTYPE_MINDIR, cpuCtx);
    cpuBuild = (int)cst;
    LOGI("cpu control build status=%d", (int)cst);
    OH_AI_ModelDestroy(&cpuModel);
    OH_AI_ContextDestroy(&cpuCtx);
  }

  OH_AI_ModelDestroy(&model);
  OH_AI_ContextDestroy(&ctx);
  // The context owns the device info added via OH_AI_ContextAddDeviceInfo; destroying
  // it separately double-frees (SIGSEGV in OH_AI_DeviceInfoDestroy, seen on-device).
  if (descs != nullptr) { OH_AI_DestroyAllNNRTDeviceDescs(&descs); }
  double total = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  char js[640];
  snprintf(js, sizeof js,
           "{\"ok\":%d,\"status\":%d,\"cpuBuild\":%d,\"dev\":\"%s\",\"latencyMs\":%.0f,\"logits\":\"%s\",\"note\":\"%s\"}",
           ok, (int)st, cpuBuild, devname.c_str(), total, logits.c_str(), note.c_str());
  return std::string(js);
}

static void Execute(napi_env, void* data) {
  auto* j = static_cast<Job*>(data);
  j->result = run_nnrt(j->path);
}

static void Complete(napi_env env, napi_status status, void* data) {
  auto* j = static_cast<Job*>(data);
  const char* s = (status == napi_ok) ? j->result.c_str() : "";
  napi_value v;
  napi_create_string_utf8(env, s, NAPI_AUTO_LENGTH, &v);
  napi_resolve_deferred(env, j->deferred, v);
  napi_delete_async_work(env, j->work);
  delete j;
}

/**
 * HiAI Foundation probe (the realistic NPU path per docs/local-jev/replacement-
 * analysis.md §7.11): can THIS app's process load libhiai.so (the system Model
 * Runtime) and see the NPU? Answers the gate question before any model-format
 * work: NNRT's HDI service is not deployed on this device, but libhiai.so's
 * HIAI_MR_* C API is present system-wide.
 */
static std::string run_hiai_probe() {
  void* h = dlopen("/system/lib64/platformsdk/libhiai.so", RTLD_NOW);
  if (h == nullptr) {
    const char* e = dlerror();
    return std::string("{\"ok\":0,\"note\":\"dlopen_failed\",\"dlerror\":\"") +
        (e != nullptr ? e : "?") + "\"}";
  }
  typedef int (*fn_int)(void);
  typedef void* (*fn_sym)(const char*);
  fn_int is_npu = (fn_int)dlsym(h, "HIAI_Foundation_IsNpuSupport");
  fn_int get_version = (fn_int)dlsym(h, "HIAI_MR_GetVersion");
  fn_sym get_symbol = (fn_sym)dlsym(h, "HIAI_Foundation_GetSymbol");
  int npu = is_npu != nullptr ? is_npu() : -1;
  int version = get_version != nullptr ? get_version() : 0;
  bool model_manager =
      get_symbol != nullptr && get_symbol("HIAI_MR_ModelManager_Create") != nullptr;
  char buf[256];
  snprintf(buf, sizeof buf,
           "{\"ok\":1,\"npu\":%d,\"version_int\":%d,\"modelManagerSym\":%s}",
           npu, version, model_manager ? "true" : "false");
  LOGI("hiai probe npu=%d version_int=%d modelManagerSym=%d", npu, version,
       (int)model_manager);
  return buf;
}

struct HiaiJob {
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  std::string result;
};

static void HiaiExecute(napi_env env, void* data) {
  auto* j = static_cast<HiaiJob*>(data);
  j->result = run_hiai_probe();
}

struct HiaiE2EJob {
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  std::string result;
};


// ---- The HiAI op battery: one --ps hiaiOps 1 run tests whether each op
// ModernBERT needs compiles on-device and executes. Each test builds a tiny
// graph (Data [+ Consts] -> op), compiles with HIAI_MR_ModelBuilder_Build,
// inits ModelManager, runs once, and records the first outputs. The op set
// covers the model's primitives: attention = BatchMatMul(adj) + Softmax +
// Mul + Add + Rsqrt/RealDiv + Exp(Sin/Cos for RoPE); FFN = MatMul + Add +
// Activation; LayerNorm is native.

struct HiaiApi {
  void* ir = nullptr;
  void* mr = nullptr;
  hiai::IModelDef* (*createModelDef)() = nullptr;
  HIAI_Status (*build)(const HIAI_MR_ModelBuildOptions*, const char*, const void*, size_t,
      HIAI_MR_BuiltModel**) = nullptr;
  HIAI_MR_ModelBuildOptions* (*boptsCreate)() = nullptr;
  HIAI_MR_ModelManager* (*mgrCreate)() = nullptr;
  HIAI_MR_ModelInitOptions* (*ioptsCreate)() = nullptr;
  HIAI_Status (*init)(HIAI_MR_ModelManager*, const HIAI_MR_ModelInitOptions*,
      const HIAI_MR_BuiltModel*, const HIAI_MR_ModelManagerListener*) = nullptr;
  HIAI_NDTensorDesc* (*getInDesc)(const HIAI_MR_BuiltModel*, size_t) = nullptr;
  HIAI_NDTensorDesc* (*getOutDesc)(const HIAI_MR_BuiltModel*, size_t) = nullptr;
  HIAI_MR_NDTensorBuffer* (*bufCreate)(const HIAI_NDTensorDesc*) = nullptr;
  void* (*bufData)(const HIAI_MR_NDTensorBuffer*) = nullptr;
  HIAI_Status (*run)(HIAI_MR_ModelManager*, HIAI_MR_NDTensorBuffer*[], int32_t,
      HIAI_MR_NDTensorBuffer*[], int32_t) = nullptr;
  size_t (*elementNum)(const HIAI_NDTensorDesc*) = nullptr;
  bool ok() const
  {
    return ir != nullptr && mr != nullptr && createModelDef != nullptr && build != nullptr &&
        boptsCreate != nullptr && mgrCreate != nullptr && ioptsCreate != nullptr &&
        init != nullptr && getInDesc != nullptr && getOutDesc != nullptr && bufCreate != nullptr &&
        bufData != nullptr && run != nullptr && elementNum != nullptr;
  }
};

static HiaiApi hiaiApi()
{
  static HiaiApi api;
  static bool tried = false;
  if (tried) { return api; }
  tried = true;
  api.ir = dlopen("/system/lib64/platformsdk/libhiai_ir.so", RTLD_NOW);
  api.mr = dlopen("/system/lib64/platformsdk/libhiai.so", RTLD_NOW);
  if (api.ir == nullptr || api.mr == nullptr) { return api; }
  api.createModelDef = (hiai::IModelDef* (*)())dlsym(api.ir, "CreateModelDef");
  api.build = (decltype(api.build))dlsym(api.mr, "HIAI_MR_ModelBuilder_Build");
  api.boptsCreate = (decltype(api.boptsCreate))dlsym(api.mr, "HIAI_MR_ModelBuildOptions_Create");
  api.mgrCreate = (decltype(api.mgrCreate))dlsym(api.mr, "HIAI_MR_ModelManager_Create");
  api.ioptsCreate = (decltype(api.ioptsCreate))dlsym(api.mr, "HIAI_MR_ModelInitOptions_Create");
  api.init = (decltype(api.init))dlsym(api.mr, "HIAI_MR_ModelManager_Init");
  api.getInDesc = (decltype(api.getInDesc))dlsym(api.mr, "HIAI_MR_BuiltModel_GetInputTensorDesc");
  api.getOutDesc = (decltype(api.getOutDesc))dlsym(api.mr, "HIAI_MR_BuiltModel_GetOutputTensorDesc");
  api.bufCreate = (decltype(api.bufCreate))dlsym(api.mr, "HIAI_MR_NDTensorBuffer_CreateFromNDTensorDesc");
  api.bufData = (decltype(api.bufData))dlsym(api.mr, "HIAI_MR_NDTensorBuffer_GetData");
  api.run = (decltype(api.run))dlsym(api.mr, "HIAI_MR_ModelManager_Run");
  api.elementNum = (decltype(api.elementNum))dlsym(api.mr, "HIAI_NDTensorDesc_GetElementNum");
  return api;
}

static void setAttrF(hiai::IOpDef* op, const char* name, float v)
{
  hiai::IAttrDef* a = op->mutable_attr()->add_attr(name);
  a->SetValueType(ge::AttrValue::VT_FLOAT);
  a->set_f(v);
}
static void setAttrI(hiai::IOpDef* op, const char* name, int64_t v)
{
  hiai::IAttrDef* a = op->mutable_attr()->add_attr(name);
  a->SetValueType(ge::AttrValue::VT_INT);
  a->set_i(v);
}
static void setAttrB(hiai::IOpDef* op, const char* name, bool v)
{
  hiai::IAttrDef* a = op->mutable_attr()->add_attr(name);
  a->SetValueType(ge::AttrValue::VT_BOOL);
  a->set_b(v);
}

static hiai::IOpDef* batteryData(hiai::IGraphDef* g, const char* name, std::vector<int64_t> dims)
{
  hiai::IOpDef* x = g->add_op();
  x->set_name(name);
  x->set_type("Data");
  hiai::ITensorDescDef* d = x->add_input_desc();
  d->set_name("x");
  d->set_dtype(ge::DT_FLOAT);
  for (int64_t dim : dims) { d->mutable_shape()->add_dim(dim); }
  hiai::ITensorDescDef* o = x->add_output_desc();
  o->set_name("y");
  o->set_dtype(ge::DT_FLOAT);
  for (int64_t dim : dims) { o->mutable_shape()->add_dim(dim); }
  g->add_input(std::string(name) + ":0");
  return x;
}

static hiai::IOpDef* batteryConstF(
    hiai::IGraphDef* g, const char* name, std::vector<int64_t> dims, const std::vector<float>& data)
{
  hiai::IOpDef* w = g->add_op();
  w->set_name(name);
  w->set_type("Const");
  hiai::IAttrDef* av = w->mutable_attr()->add_attr("value");
  av->SetValueType(ge::AttrValue::VT_TENSOR);
  hiai::ITensorDef* td = av->mutable_t();
  hiai::ITensorDescDef* wd = td->mutable_desc();
  wd->set_dtype(ge::DT_FLOAT);
  for (int64_t dim : dims) { wd->mutable_shape()->add_dim(dim); }
  td->set_data(std::string((const char*)data.data(), data.size() * sizeof(float)));
  hiai::ITensorDescDef* wo = w->add_output_desc();
  wo->set_name("y");
  wo->set_dtype(ge::DT_FLOAT);
  for (int64_t dim : dims) { wo->mutable_shape()->add_dim(dim); }
  return w;
}

static hiai::IOpDef* batteryConstI(
    hiai::IGraphDef* g, const char* name, std::vector<int64_t> dims, const std::vector<int32_t>& data)
{
  hiai::IOpDef* w = g->add_op();
  w->set_name(name);
  w->set_type("Const");
  hiai::IAttrDef* av = w->mutable_attr()->add_attr("value");
  av->SetValueType(ge::AttrValue::VT_TENSOR);
  hiai::ITensorDef* td = av->mutable_t();
  hiai::ITensorDescDef* wd = td->mutable_desc();
  wd->set_dtype(ge::DT_INT32);
  for (int64_t dim : dims) { wd->mutable_shape()->add_dim(dim); }
  td->set_data(std::string((const char*)data.data(), data.size() * sizeof(int32_t)));
  hiai::ITensorDescDef* wo = w->add_output_desc();
  wo->set_name("y");
  wo->set_dtype(ge::DT_INT32);
  for (int64_t dim : dims) { wo->mutable_shape()->add_dim(dim); }
  return w;
}

static std::string batteryRunOne(const HiaiApi& api, const char* name, hiai::IModelDef* model,
    const std::vector<float>& fill)
{
  std::string out = "{\"name\":\"";
  out += name;
  out += "\"";
  size_t sz = model->GetModelDefSize();
  std::vector<uint8_t> buf(sz);
  if (!model->SaveTo(buf.data(), sz)) { out += ",\"note\":\"serialize_failed\"}"; return out; }
  {
    static bool dumped = false;
    if (!dumped) {
      dumped = true;
      FILE* f = fopen("/data/storage/el2/base/haps/entry/files/battery-model.pb", "wb");
      if (f != nullptr) { fwrite(buf.data(), 1, sz, f); fclose(f); }
    }
  }
  HIAI_MR_ModelBuildOptions* bopts = api.boptsCreate();
  HIAI_MR_BuiltModel* built = nullptr;
  // The builder matches the model by name: the modelName argument must be the
  // model def's own name, not the test label.
  HIAI_Status st = api.build(bopts, model->name().c_str(), buf.data(), sz, &built);
  out += ",\"build\":" + std::to_string((int)st);
  if (st != HIAI_SUCCESS) { out += "}"; return out; }
  HIAI_MR_ModelManager* mgr = api.mgrCreate();
  HIAI_MR_ModelInitOptions* iopts = api.ioptsCreate();
  st = api.init(mgr, iopts, built, nullptr);
  out += ",\"init\":" + std::to_string((int)st);
  if (st != HIAI_SUCCESS) { out += "}"; return out; }
  HIAI_NDTensorDesc* inDesc = api.getInDesc(built, 0);
  HIAI_NDTensorDesc* outDesc = api.getOutDesc(built, 0);
  HIAI_MR_NDTensorBuffer* in = api.bufCreate(inDesc);
  HIAI_MR_NDTensorBuffer* obuf = api.bufCreate(outDesc);
  float* ip = (float*)api.bufData(in);
  size_t elems = api.elementNum(inDesc);
  for (size_t i = 0; i < elems && i < fill.size(); i++) { ip[i] = fill[i]; }
  for (size_t i = fill.size(); i < elems; i++) { ip[i] = 1.f; }
  HIAI_MR_NDTensorBuffer* tin[1] = {in};
  HIAI_MR_NDTensorBuffer* tout[1] = {obuf};
  st = api.run(mgr, tin, 1, tout, 1);
  out += ",\"run\":" + std::to_string((int)st);
  if (st == HIAI_SUCCESS) {
    float* op = (float*)api.bufData(obuf);
    char vals[96];
    snprintf(vals, sizeof vals, ",\"v\":[%.3f,%.3f,%.3f]", op[0], op[1], op[2]);
    out += vals;
  }
  out += "}";
  return out;
}

static std::string run_hiai_ops_battery()
{
  HiaiApi api = hiaiApi();
  if (!api.ok()) { return "{\"ok\":0,\"note\":\"dlsym_failed\"}"; }
  std::vector<std::string> results;

  auto model0 = [&api]() { return api.createModelDef(); };

  // matmul: [1,4] x [4,1] = 1+2+3+4
  {
    hiai::IModelDef* m = model0();
    m->set_name("t_matmul");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    hiai::IOpDef* x = batteryData(g, "x", {1, 4});
    batteryConstF(g, "w", {4, 1}, {1.f, 2.f, 3.f, 4.f});
    hiai::IOpDef* mm = g->add_op();
    mm->set_name("mm");
    mm->set_type("MatMul");
    mm->add_input("x:0");
    mm->add_input("w:0");
    hiai::ITensorDescDef* mi1 = mm->add_input_desc();
    mi1->set_name("x1");
    mi1->set_dtype(ge::DT_FLOAT);
    mi1->mutable_shape()->add_dim(1);
    mi1->mutable_shape()->add_dim(4);
    hiai::ITensorDescDef* mi2 = mm->add_input_desc();
    mi2->set_name("x2");
    mi2->set_dtype(ge::DT_FLOAT);
    mi2->mutable_shape()->add_dim(4);
    mi2->mutable_shape()->add_dim(1);
    hiai::ITensorDescDef* o = mm->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(1);
    g->add_output("mm:0");
    results.push_back(batteryRunOne(api, "MatMul", m, {1.f, 1.f, 1.f, 1.f}));
  }
  // add / mul: [1,4] + Const[1,4]
  for (const char* ty : {"Add", "Mul"}) {
    hiai::IModelDef* m = model0();
    m->set_name(std::string("t_") + (ty[0] == 'A' ? "add" : "mul"));
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    hiai::IOpDef* x = batteryData(g, "x", {1, 4});
    batteryConstF(g, "w", {1, 4}, {1.f, 2.f, 3.f, 4.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type(ty);
    opn->add_input("x:0");
    opn->add_input("w:0");
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name(k == 0 ? "x1" : "x2");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(1);
      mi->mutable_shape()->add_dim(4);
    }
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(4);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, ty, m, {1.f, 1.f, 1.f, 1.f}));
  }
  // unary: sqrt / rsqrt / exp / sin / cos on [1,4]
  for (const char* ty : {"Sqrt", "Rsqrt", "Exp", "Sin", "Cos"}) {
    hiai::IModelDef* m = model0();
    m->set_name(std::string("t_") + (char)tolower(ty[0]) + std::string(ty + 1));
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 4});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type(ty);
    opn->add_input("x:0");
    hiai::ITensorDescDef* mi = opn->add_input_desc();
    mi->set_name("x");
    mi->set_dtype(ge::DT_FLOAT);
    mi->mutable_shape()->add_dim(1);
    mi->mutable_shape()->add_dim(4);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(4);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, ty, m, {4.f, 9.f, 1.f, 2.f}));
  }
  // realdiv: [1,4] / Const[1,4]
  {
    hiai::IModelDef* m = model0();
    m->set_name("t_div");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 4});
    batteryConstF(g, "w", {1, 4}, {1.f, 2.f, 4.f, 8.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("RealDiv");
    opn->add_input("x:0");
    opn->add_input("w:0");
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name(k == 0 ? "x1" : "x2");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(1);
      mi->mutable_shape()->add_dim(4);
    }
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(4);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "RealDiv", m, {8.f, 8.f, 8.f, 8.f}));
  }
  // layernorm: x[1,4], gamma/beta Const[4]
  {
    hiai::IModelDef* m = model0();
    m->set_name("t_ln");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 4});
    batteryConstF(g, "gamma", {4}, {1.f, 1.f, 1.f, 1.f});
    batteryConstF(g, "beta", {4}, {0.f, 0.f, 0.f, 0.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("LayerNorm");
    opn->add_input("x:0");
    opn->add_input("gamma:0");
    opn->add_input("beta:0");
    {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name("x");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(1);
      mi->mutable_shape()->add_dim(4);
      for (const char* n : {"gamma", "beta"}) {
        hiai::ITensorDescDef* g2 = opn->add_input_desc();
        g2->set_name(n);
        g2->set_dtype(ge::DT_FLOAT);
        g2->mutable_shape()->add_dim(4);
      }
    }
    setAttrI(opn, "begin_norm_axis", 1);
    setAttrI(opn, "begin_params_axis", 1);
    setAttrF(opn, "epsilon", 1e-5f);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(4);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "LayerNorm", m, {1.f, 2.f, 3.f, 4.f}));
  }
  // softmax: [1,4], axis -1
  {
    hiai::IModelDef* m = model0();
    m->set_name("t_sm");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 4});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("Softmax");
    opn->add_input("x:0");
    {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name("x");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(1);
      mi->mutable_shape()->add_dim(4);
    }
    setAttrI(opn, "axis", -1);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(4);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "Softmax", m, {1.f, 2.f, 3.f, 4.f}));
  }
  // batchmatmul: [1,2,2] x [1,2,2] (identity-ish)
  {
    hiai::IModelDef* m = model0();
    m->set_name("t_bmm");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 2, 2});
    batteryConstF(g, "w", {1, 2, 2}, {1.f, 0.f, 0.f, 1.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("BatchMatMul");
    opn->add_input("x:0");
    opn->add_input("w:0");
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name(k == 0 ? "x1" : "x2");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(1);
      mi->mutable_shape()->add_dim(2);
      mi->mutable_shape()->add_dim(2);
    }
    setAttrB(opn, "adj_x1", false);
    setAttrB(opn, "adj_x2", false);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "BatchMatMul", m, {1.f, 2.f, 3.f, 4.f}));
  }
  // === Layout battery: can a transposed-space attention be expressed? ===
  // The attention blocker is adj_x2 (Q @ K^T): shape inference rejects it on
  // every HiAI tested. In a fully transposed residual stream ([d, s] instead
  // of [s, d]), the score matmul becomes adj_x1 (K^T @ Q^T -> K @ Q^T), the
  // value product needs no adjoint at all, and every weight projection uses a
  // pre-transposed Const. The tests below probe exactly the op forms that
  // construction needs.
  {
    // MatMul adj_x1: A[3,2]^T x B[3,2] = [2,2]; A=ones -> column sums of B.
    hiai::IModelDef* m = model0();
    m->set_name("t_mm_adjx1");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {3, 2});
    batteryConstF(g, "w", {3, 2}, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f});
    hiai::IOpDef* mm = g->add_op();
    mm->set_name("mm");
    mm->set_type("MatMul");
    mm->add_input("x:0");
    mm->add_input("w:0");
    hiai::ITensorDescDef* mi1 = mm->add_input_desc();
    mi1->set_name("x1");
    mi1->set_dtype(ge::DT_FLOAT);
    mi1->mutable_shape()->add_dim(3);
    mi1->mutable_shape()->add_dim(2);
    hiai::ITensorDescDef* mi2 = mm->add_input_desc();
    mi2->set_name("x2");
    mi2->set_dtype(ge::DT_FLOAT);
    mi2->mutable_shape()->add_dim(3);
    mi2->mutable_shape()->add_dim(2);
    setAttrB(mm, "adj_x1", true);
    setAttrB(mm, "adj_x2", false);
    hiai::ITensorDescDef* o = mm->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(2);
    g->add_output("mm:0");
    results.push_back(batteryRunOne(api, "MatMul(adj_x1)", m, {1.f, 1.f, 1.f, 1.f, 1.f, 1.f}));
  }
  {
    // MatMul both adjoints: A[2,3]^T x B[2,2]^T = [3,2].
    hiai::IModelDef* m = model0();
    m->set_name("t_mm_adjboth");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {2, 3});
    batteryConstF(g, "w", {2, 2}, {1.f, 2.f, 3.f, 4.f});
    hiai::IOpDef* mm = g->add_op();
    mm->set_name("mm");
    mm->set_type("MatMul");
    mm->add_input("x:0");
    mm->add_input("w:0");
    hiai::ITensorDescDef* mi1 = mm->add_input_desc();
    mi1->set_name("x1");
    mi1->set_dtype(ge::DT_FLOAT);
    mi1->mutable_shape()->add_dim(2);
    mi1->mutable_shape()->add_dim(3);
    hiai::ITensorDescDef* mi2 = mm->add_input_desc();
    mi2->set_name("x2");
    mi2->set_dtype(ge::DT_FLOAT);
    mi2->mutable_shape()->add_dim(2);
    mi2->mutable_shape()->add_dim(2);
    setAttrB(mm, "adj_x1", true);
    setAttrB(mm, "adj_x2", true);
    hiai::ITensorDescDef* o = mm->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(3);
    o->mutable_shape()->add_dim(2);
    g->add_output("mm:0");
    results.push_back(batteryRunOne(api, "MatMul(adj_x1+x2)", m, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f}));
  }
  {
    // BatchMatMul adj_x1: [1,3,2]^T x [1,3,2] per batch.
    hiai::IModelDef* m = model0();
    m->set_name("t_bmm_adjx1");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 3, 2});
    batteryConstF(g, "w", {1, 3, 2}, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("BatchMatMul");
    opn->add_input("x:0");
    opn->add_input("w:0");
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name(k == 0 ? "x1" : "x2");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(1);
      mi->mutable_shape()->add_dim(3);
      mi->mutable_shape()->add_dim(2);
    }
    setAttrB(opn, "adj_x1", true);
    setAttrB(opn, "adj_x2", false);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "BatchMatMul(adj_x1)", m, {1.f, 1.f, 1.f, 1.f, 1.f, 1.f}));
  }
  {
    // Softmax over the column axis (-2): the transposed-space attention needs
    // to normalise scores^T along dim 0 of its trailing [s, s].
    hiai::IModelDef* m = model0();
    m->set_name("t_sm_axis_m2");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 2, 2});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("Softmax");
    opn->add_input("x:0");
    hiai::ITensorDescDef* mi = opn->add_input_desc();
    mi->set_name("x");
    mi->set_dtype(ge::DT_FLOAT);
    mi->mutable_shape()->add_dim(1);
    mi->mutable_shape()->add_dim(2);
    mi->mutable_shape()->add_dim(2);
    setAttrI(opn, "axis", -2);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "Softmax(axis=-2)", m, {1.f, 2.f, 3.f, 4.f}));
  }
  // Broadcast of a [1, n] row over [d, n] rows: the transposed-space
  // LayerNorm/statistics replacement broadcasts per-column means.
  for (const char* ty : {"Add", "Mul", "RealDiv"}) {
    hiai::IModelDef* m = model0();
    m->set_name(std::string("t_bcast_") + (ty[0] == 'A' ? "add" : (ty[0] == 'M' ? "mul" : "div")));
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {3, 2});
    batteryConstF(g, "w", {1, 2}, {2.f, 3.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type(ty);
    opn->add_input("x:0");
    opn->add_input("w:0");
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name(k == 0 ? "x1" : "x2");
      mi->set_dtype(ge::DT_FLOAT);
      if (k == 0) {
        mi->mutable_shape()->add_dim(3);
        mi->mutable_shape()->add_dim(2);
      } else {
        mi->mutable_shape()->add_dim(1);
        mi->mutable_shape()->add_dim(2);
      }
    }
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(3);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, (std::string(ty) + " broadcast[3,2]x[1,2]").c_str(),
        m, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f}));
  }
  {
    // SplitD along dim 0: heads are cut out of the feature rows in the
    // transposed stream.
    hiai::IModelDef* m = model0();
    m->set_name("t_split0");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {4, 2});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("SplitD");
    opn->add_input("x:0");
    hiai::ITensorDescDef* mi = opn->add_input_desc();
    mi->set_name("x");
    mi->set_dtype(ge::DT_FLOAT);
    mi->mutable_shape()->add_dim(4);
    mi->mutable_shape()->add_dim(2);
    setAttrI(opn, "split_dim", 0);
    setAttrI(opn, "num_split", 2);
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* od = opn->add_output_desc();
      od->set_name(k == 0 ? "y1" : "y2");
      od->set_dtype(ge::DT_FLOAT);
      od->mutable_shape()->add_dim(2);
      od->mutable_shape()->add_dim(2);
    }
    g->add_output("op:0");
    g->add_output("op:1");
    results.push_back(batteryRunOne(api, "SplitD(axis=0)", m, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f, 7.f, 8.f}));
  }
  // Round 2: the remaining transposed-stream forms.
  {
    // LayerNorm with the normalisation axis on dim 0 ([d, s] streams).
    hiai::IModelDef* m = model0();
    m->set_name("t_ln_axis0");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {3, 2});
    batteryConstF(g, "g0", {1, 2}, {1.f, 1.f});
    batteryConstF(g, "b0", {1, 2}, {0.f, 0.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("LayerNorm");
    opn->add_input("x:0");
    opn->add_input("g0:0");
    opn->add_input("b0:0");
    hiai::ITensorDescDef* mi = opn->add_input_desc();
    mi->set_name("x");
    mi->set_dtype(ge::DT_FLOAT);
    mi->mutable_shape()->add_dim(3);
    mi->mutable_shape()->add_dim(2);
    setAttrI(opn, "begin_norm_axis", 0);
    setAttrI(opn, "begin_params_axis", 2);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(3);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "LayerNorm(axis=0)", m, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f}));
  }
  {
    // LayerNorm over the leading dims via a negative axis.
    hiai::IModelDef* m = model0();
    m->set_name("t_ln_axism2");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {3, 2});
    batteryConstF(g, "g0", {1, 2}, {1.f, 1.f});
    batteryConstF(g, "b0", {1, 2}, {0.f, 0.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("LayerNorm");
    opn->add_input("x:0");
    opn->add_input("g0:0");
    opn->add_input("b0:0");
    hiai::ITensorDescDef* mi = opn->add_input_desc();
    mi->set_name("x");
    mi->set_dtype(ge::DT_FLOAT);
    mi->mutable_shape()->add_dim(3);
    mi->mutable_shape()->add_dim(2);
    setAttrI(opn, "begin_norm_axis", -2);
    setAttrI(opn, "begin_params_axis", 2);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(3);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "LayerNorm(axis=-2)", m, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f}));
  }
  {
    // Sub with the leading-dim broadcast ([3,2] - [1,2]).
    hiai::IModelDef* m = model0();
    m->set_name("t_bcast_sub");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {3, 2});
    batteryConstF(g, "w", {1, 2}, {2.f, 3.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("Sub");
    opn->add_input("x:0");
    opn->add_input("w:0");
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name(k == 0 ? "x1" : "x2");
      mi->set_dtype(ge::DT_FLOAT);
      if (k == 0) {
        mi->mutable_shape()->add_dim(3);
        mi->mutable_shape()->add_dim(2);
      } else {
        mi->mutable_shape()->add_dim(1);
        mi->mutable_shape()->add_dim(2);
      }
    }
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(3);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "Sub broadcast[3,2]x[1,2]", m, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f}));
  }
  {
    // ConcatD along dim 0 (head outputs stack in the transposed stream).
    hiai::IModelDef* m = model0();
    m->set_name("t_concat0");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {2, 2});
    batteryConstF(g, "w", {2, 2}, {9.f, 8.f, 7.f, 6.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("ConcatD");
    opn->add_input("x:0");
    opn->add_input("w:0");
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name(k == 0 ? "x1" : "x2");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(2);
      mi->mutable_shape()->add_dim(2);
    }
    setAttrI(opn, "concat_dim", 0);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(4);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "ConcatD(axis=0)", m, {1.f, 2.f, 3.f, 4.f}));
  }
  {
    // Pow (x^2): the sqrt-free LayerNorm fallback needs a power op.
    hiai::IModelDef* m = model0();
    m->set_name("t_pow");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 4});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("Pow");
    opn->add_input("x:0");
    hiai::ITensorDescDef* mi = opn->add_input_desc();
    mi->set_name("x");
    mi->set_dtype(ge::DT_FLOAT);
    mi->mutable_shape()->add_dim(1);
    mi->mutable_shape()->add_dim(4);
    setAttrF(opn, "power", 2.f);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(4);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "Pow(x^2)", m, {1.f, 2.f, 3.f, 4.f}));
  }
  // Round 3: trailing-dim broadcast and batched (multi-head) forms.
  for (int variant = 0; variant < 2; variant++) {
    // Add / Mul with the broadcast on the LAST dim ([3,2] x [3,1]) -- the
    // transposed LayerNorm gamma/beta are per-feature rows.
    hiai::IModelDef* m = model0();
    m->set_name(variant == 0 ? "t_bcast_trail_add" : "t_bcast_trail_mul");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {3, 2});
    batteryConstF(g, "w", {3, 1}, {2.f, 3.f, 4.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type(variant == 0 ? "Add" : "Mul");
    opn->add_input("x:0");
    opn->add_input("w:0");
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name(k == 0 ? "x1" : "x2");
      mi->set_dtype(ge::DT_FLOAT);
      if (k == 0) {
        mi->mutable_shape()->add_dim(3);
        mi->mutable_shape()->add_dim(2);
      } else {
        mi->mutable_shape()->add_dim(3);
        mi->mutable_shape()->add_dim(1);
      }
    }
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(3);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, variant == 0 ? "Add bcast[3,2]x[3,1]" : "Mul bcast[3,2]x[3,1]",
        m, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f}));
  }
  {
    // BatchMatMul(adj_x1) with a real batch (12 heads become one batched op).
    hiai::IModelDef* m = model0();
    m->set_name("t_bmm2_adjx1");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {2, 3, 2});
    batteryConstF(g, "w", {2, 3, 2}, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f, 6.f, 5.f, 4.f, 3.f, 2.f, 1.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("BatchMatMul");
    opn->add_input("x:0");
    opn->add_input("w:0");
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name(k == 0 ? "x1" : "x2");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(2);
      mi->mutable_shape()->add_dim(3);
      mi->mutable_shape()->add_dim(2);
    }
    setAttrB(opn, "adj_x1", true);
    setAttrB(opn, "adj_x2", false);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "BatchMatMul(adj_x1,b=2)", m,
        {1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f}));
  }
  {
    // BatchMatMul no-adj with a real batch ([2,3,2] x [2,2,2]).
    hiai::IModelDef* m = model0();
    m->set_name("t_bmm2_plain");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {2, 3, 2});
    batteryConstF(g, "w", {2, 2, 2}, {1.f, 2.f, 3.f, 4.f, 4.f, 3.f, 2.f, 1.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("BatchMatMul");
    opn->add_input("x:0");
    opn->add_input("w:0");
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name(k == 0 ? "x1" : "x2");
      mi->set_dtype(ge::DT_FLOAT);
      if (k == 0) {
        mi->mutable_shape()->add_dim(2);
        mi->mutable_shape()->add_dim(3);
        mi->mutable_shape()->add_dim(2);
      } else {
        mi->mutable_shape()->add_dim(2);
        mi->mutable_shape()->add_dim(2);
        mi->mutable_shape()->add_dim(2);
      }
    }
    setAttrB(opn, "adj_x1", false);
    setAttrB(opn, "adj_x2", false);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(3);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "BatchMatMul(b=2)", m,
        {1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f}));
  }
  {
    // Softmax(axis=-2) on a batched [2,2,2].
    hiai::IModelDef* m = model0();
    m->set_name("t_sm2_m2");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {2, 2, 2});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("Softmax");
    opn->add_input("x:0");
    hiai::ITensorDescDef* mi = opn->add_input_desc();
    mi->set_name("x");
    mi->set_dtype(ge::DT_FLOAT);
    mi->mutable_shape()->add_dim(2);
    mi->mutable_shape()->add_dim(2);
    mi->mutable_shape()->add_dim(2);
    setAttrI(opn, "axis", -2);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "Softmax(-2,b=2)", m, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f, 7.f, 8.f}));
  }
  {
    // Mul of [2,3,3] by [3,3]: the attention mask broadcasts over the batch.
    hiai::IModelDef* m = model0();
    m->set_name("t_maskmul");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {2, 3, 3});
    batteryConstF(g, "w", {3, 3}, {1.f, 0.f, 0.f, 0.f, 1.f, 0.f, 0.f, 0.f, 1.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("Mul");
    opn->add_input("x:0");
    opn->add_input("w:0");
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name(k == 0 ? "x1" : "x2");
      mi->set_dtype(ge::DT_FLOAT);
      if (k == 0) {
        mi->mutable_shape()->add_dim(2);
        mi->mutable_shape()->add_dim(3);
        mi->mutable_shape()->add_dim(3);
      } else {
        mi->mutable_shape()->add_dim(3);
        mi->mutable_shape()->add_dim(3);
      }
    }
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(3);
    o->mutable_shape()->add_dim(3);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "Mul [2,3,3]x[3,3]", m,
        {1.f, 2.f, 3.f, 4.f, 5.f, 6.f, 7.f, 8.f, 9.f, 10.f, 11.f, 12.f, 13.f, 14.f, 15.f, 16.f, 17.f, 18.f}));
  }
  // concat: Data[1,2] + Const[1,2] on dim 1
  {
    hiai::IModelDef* m = model0();
    m->set_name("t_cat");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 2});
    batteryConstF(g, "w", {1, 2}, {9.f, 9.f});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("ConcatD");
    opn->add_input("x:0");
    opn->add_input("w:0");
    for (int k = 0; k < 2; k++) {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name(k == 0 ? "x1" : "x2");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(1);
      mi->mutable_shape()->add_dim(2);
    }
    setAttrI(opn, "concat_dim", 1);
    setAttrI(opn, "N", 2);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(4);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "ConcatD", m, {1.f, 2.f}));
  }
  // activation: [1,4], default mode
  {
    hiai::IModelDef* m = model0();
    m->set_name("t_act");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 4});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("Activation");
    opn->add_input("x:0");
    {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name("x");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(1);
      mi->mutable_shape()->add_dim(4);
    }
    // mode 15 = GeLU (the ModernBERT MLP activation); values below are
    // gelu(1,2,3,4) ~ 0.841, 1.955, 2.996, 4.000.
    setAttrI(opn, "mode", 15);
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(4);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "ActivationGeLU", m, {1.f, 2.f, 3.f, 4.f}));
  }
  // transpose: [1,2,3] -> perm(1,0,2) -> [2,1,3] (undocumented in the old
  // public op list; the runtime compiler inserts its own transposes, so the
  // op likely exists)
  {
    hiai::IModelDef* m = model0();
    m->set_name("t_transpose");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 2, 3});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("TransposeD");
    opn->add_input("x:0");
    {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name("x");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(1);
      mi->mutable_shape()->add_dim(2);
      mi->mutable_shape()->add_dim(3);
    }
    hiai::IAttrDef* avd = opn->mutable_attr()->add_attr("perm");
    avd->SetValueType(ge::AttrValue::VT_LIST_INT);
    hiai::IAttrListDef* lstd = avd->mutable_list();
    for (int64_t pv : {1, 0, 2}) { lstd->add_i(pv); }
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(3);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "TransposeD", m, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f}));
  }
  {
    hiai::IModelDef* m = model0();
    m->set_name("t_transpose2");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 2, 3});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("Transpose");
    opn->add_input("x:0");
    {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name("x");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(1);
      mi->mutable_shape()->add_dim(2);
      mi->mutable_shape()->add_dim(3);
    }
    hiai::IAttrDef* av = opn->mutable_attr()->add_attr("perm");
    av->SetValueType(ge::AttrValue::VT_LIST_INT);
    hiai::IAttrListDef* lst = av->mutable_list();
    for (int64_t pv : {1, 0, 2}) { lst->add_i(pv); }
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(1);
    o->mutable_shape()->add_dim(3);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "Transpose(list-attr)", m, {1.f, 2.f, 3.f, 4.f, 5.f, 6.f}));
  }
  // reshape: [1,4] -> [2,2] with an int32 shape Const input
  {
    hiai::IModelDef* m = model0();
    m->set_name("t_reshape");
    hiai::IGraphDef* g = m->add_graph();
    g->set_name("g");
    batteryData(g, "x", {1, 4});
    batteryConstI(g, "shape", {2}, {2, 2});
    hiai::IOpDef* opn = g->add_op();
    opn->set_name("op");
    opn->set_type("Reshape");
    opn->add_input("x:0");
    opn->add_input("shape:0");
    {
      hiai::ITensorDescDef* mi = opn->add_input_desc();
      mi->set_name("x");
      mi->set_dtype(ge::DT_FLOAT);
      mi->mutable_shape()->add_dim(1);
      mi->mutable_shape()->add_dim(4);
      hiai::ITensorDescDef* ms = opn->add_input_desc();
      ms->set_name("shape");
      ms->set_dtype(ge::DT_INT32);
      ms->mutable_shape()->add_dim(2);
    }
    hiai::ITensorDescDef* o = opn->add_output_desc();
    o->set_name("y");
    o->set_dtype(ge::DT_FLOAT);
    o->mutable_shape()->add_dim(2);
    o->mutable_shape()->add_dim(2);
    g->add_output("op:0");
    results.push_back(batteryRunOne(api, "Reshape", m, {1.f, 2.f, 3.f, 4.f}));
  }

  std::string out = "{\"ok\":1,\"tests\":[";
  for (size_t i = 0; i < results.size(); i++) {
    if (i > 0) { out += ","; }
    out += results[i];
  }
  out += "]}";
  return out;
}

static std::string run_hiai_e2e();

static void HiaiE2EExecute(napi_env env, void* data) {
  auto* j = static_cast<HiaiE2EJob*>(data);
  j->result = run_hiai_e2e();
}

static void HiaiE2EComplete(napi_env env, napi_status status, void* data) {
  auto* j = static_cast<HiaiE2EJob*>(data);
  const char* s = (status == napi_ok) ? j->result.c_str() : "";
  napi_value v;
  napi_create_string_utf8(env, s, NAPI_AUTO_LENGTH, &v);
  napi_resolve_deferred(env, j->deferred, v);
  napi_delete_async_work(env, j->work);
  delete j;
}

static void HiaiOpsExecute(napi_env env, void* data) {
  auto* j = static_cast<HiaiE2EJob*>(data);
  j->result = run_hiai_ops_battery();
}

static napi_value HiaiOps(napi_env env, napi_callback_info info) {
  auto* j = new HiaiE2EJob();
  j->result = "";
  napi_value p;
  napi_create_promise(env, &j->deferred, &p);
  napi_value nm;
  napi_create_string_utf8(env, "msnnrt.hiaiOps", NAPI_AUTO_LENGTH, &nm);
  napi_create_async_work(env, nullptr, nm, HiaiOpsExecute, HiaiE2EComplete, j, &j->work);
  napi_queue_async_work(env, j->work);
  return p;
}

static napi_value HiaiE2E(napi_env env, napi_callback_info info) {
  auto* j = new HiaiE2EJob();
  j->result = "";
  napi_value p;
  napi_create_promise(env, &j->deferred, &p);
  napi_value nm;
  napi_create_string_utf8(env, "msnnrt.hiaiE2E", NAPI_AUTO_LENGTH, &nm);
  napi_create_async_work(env, nullptr, nm, HiaiE2EExecute, HiaiE2EComplete, j, &j->work);
  napi_queue_async_work(env, j->work);
  return p;
}

static void HiaiComplete(napi_env env, napi_status status, void* data) {
  auto* j = static_cast<HiaiJob*>(data);
  const char* s = (status == napi_ok) ? j->result.c_str() : "";
  napi_value v;
  napi_create_string_utf8(env, s, NAPI_AUTO_LENGTH, &v);
  napi_resolve_deferred(env, j->deferred, v);
  napi_delete_async_work(env, j->work);
  delete j;
}

/**
 * The large-model HiAI test: read a model.pb + input tensor from the app's
 * filesDir (downloaded by the ArkTS side), build with the on-device compiler,
 * run, and return the logits. This is the device-side validation of the full
 * generated graph (hiai-gen.py output, offline parity 0.0017).
 */
static std::string run_hiai_model_test(const std::string& modelPath, const std::string& inputPath) {
  HiaiApi api = hiaiApi();
  if (!api.ok()) { return "{\"ok\":0,\"note\":\"dlsym_failed\"}"; }
  // Read the model
  FILE* mf = fopen(modelPath.c_str(), "rb");
  if (mf == nullptr) { return "{\"ok\":0,\"note\":\"model_open_failed\"}"; }
  fseek(mf, 0, SEEK_END);
  long msz = ftell(mf);
  fseek(mf, 0, SEEK_SET);
  std::vector<uint8_t> mbuf(msz);
  if (fread(mbuf.data(), 1, msz, mf) != (size_t)msz) { fclose(mf); return "{\"ok\":0,\"note\":\"model_read_failed\"}"; }
  fclose(mf);
  LOGI("hiai model: read %ld bytes", msz);
  // Read the input (f32 [seq, 768])
  FILE* inf = fopen(inputPath.c_str(), "rb");
  if (inf == nullptr) { return "{\"ok\":0,\"note\":\"input_open_failed\"}"; }
  fseek(inf, 0, SEEK_END);
  long isz = ftell(inf);
  fseek(inf, 0, SEEK_SET);
  std::vector<uint8_t> ibuf(isz);
  if (fread(ibuf.data(), 1, isz, inf) != (size_t)isz) { fclose(inf); return "{\"ok\":0,\"note\":\"input_read_failed\"}"; }
  fclose(inf);
  long seq = isz / (768 * 4);
  LOGI("hiai model: input %ld bytes = seq %ld", isz, seq);
  // Build
  auto t0 = std::chrono::steady_clock::now();
  HIAI_MR_ModelBuildOptions* bopts = api.boptsCreate();
  HIAI_MR_BuiltModel* built = nullptr;
  // The on-device build appears nondeterministic: identical graphs have
  // been observed to fail once and pass on a retry (probe w18 vs w25).
  // Retry a few times before giving up.
  int build_tries = 3;
  HIAI_Status st = HIAI_SUCCESS;
  for (int attempt = 0; attempt < build_tries; attempt++) {
    st = api.build(bopts, "laya_npu", mbuf.data(), mbuf.size(), &built);
    if (st == HIAI_SUCCESS) { break; }
    LOGI("hiai model: build attempt %d rc=%d, retrying", attempt, (int)st);
  }
  double buildMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  LOGI("hiai model: build rc=%d, %.0f ms", (int)st, buildMs);
  if (st != HIAI_SUCCESS) {
    return "{\"ok\":0,\"note\":\"build_failed\",\"rc\":" + std::to_string((int)st) +
      ",\"buildMs\":" + std::to_string(buildMs) + "}";
  }
  // Init
  t0 = std::chrono::steady_clock::now();
  HIAI_MR_ModelManager* mgr = api.mgrCreate();
  HIAI_MR_ModelInitOptions* iopts = api.ioptsCreate();
  st = api.init(mgr, iopts, built, nullptr);
  double initMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  LOGI("hiai model: init rc=%d, %.0f ms", (int)st, initMs);
  if (st != HIAI_SUCCESS) {
    return "{\"ok\":0,\"note\":\"init_failed\",\"rc\":" + std::to_string((int)st) + "}";
  }
  // Prepare input/output buffers. Every declared input gets a buffer: input
  // 0 receives the file's contents, the rest are zero-filled -- the runtime
  // requires one buffer per input, and probes with several Data inputs
  // otherwise fail at run.
  HIAI_NDTensorDesc* outDesc = api.getOutDesc(built, 0);
  HIAI_MR_NDTensorBuffer* out = api.bufCreate(outDesc);
  size_t nInputs = 0;
  while (api.getInDesc(built, nInputs) != nullptr) { nInputs++; }
  LOGI("hiai model: %zu inputs", nInputs);
  HIAI_MR_NDTensorBuffer* tin[8] = {nullptr};
  size_t nUse = nInputs < 8 ? nInputs : 8;
  // The input file is the concatenation of every input's bytes (the batched
  // graph takes emb, tadd and pmask in order); the remainder is zero-filled.
  size_t consumed = 0;
  for (size_t k = 0; k < nUse; k++) {
    HIAI_NDTensorDesc* d = api.getInDesc(built, k);
    tin[k] = api.bufCreate(d);
    float* ip = (float*)api.bufData(tin[k]);
    size_t cap = api.elementNum(d) * sizeof(float);
    size_t take = 0;
    if (consumed < (size_t)isz) {
      take = (size_t)isz - consumed;
      if (take > cap) { take = cap; }
      memcpy(ip, ibuf.data() + consumed, take);
    }
    for (size_t b = take; b < cap; b++) { ((uint8_t*)ip)[b] = 0; }
    consumed += take;
  }
  HIAI_MR_NDTensorBuffer* tout[1] = {out};
  // Warm-up + timed run
  t0 = std::chrono::steady_clock::now();
  st = api.run(mgr, tin, (int)nUse, tout, 1);
  double runMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  LOGI("hiai model: run rc=%d, %.0f ms", (int)st, runMs);
  if (st != HIAI_SUCCESS) {
    return "{\"ok\":0,\"note\":\"run_failed\",\"rc\":" + std::to_string((int)st) + "}";
  }
  float* op = (float*)api.bufData(out);
  int nout = api.elementNum(outDesc);
  char vals[256];
  snprintf(vals, sizeof vals, "[%.4f,%.4f,%.4f,%.4f]", op[0], op[1], op[2], op[3]);
  char r[512];
  snprintf(r, sizeof r,
    "{\"ok\":1,\"buildMs\":%.0f,\"initMs\":%.0f,\"runMs\":%.0f,\"seq\":%ld,\"nout\":%d,\"logits\":%s}",
    buildMs, initMs, runMs, seq, nout, vals);
  return r;
}

struct HiaiModelJob {
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  std::string modelPath;
  std::string inputPath;
  std::string result;
  std::vector<uint8_t> modelData;
  std::vector<uint8_t> inputData;
  napi_ref modelBuf = nullptr;
  napi_ref inputBuf = nullptr;
};

static void HiaiModelExecute(napi_env env, void* data) {
  auto* j = static_cast<HiaiModelJob*>(data);
  j->result = run_hiai_model_test(j->modelPath, j->inputPath);
}

static std::string run_hiai_model_buffer(const std::vector<uint8_t>& mbuf,
    const std::vector<uint8_t>& ibuf) {
  HiaiApi api = hiaiApi();
  if (!api.ok()) { return "{\"ok\":0,\"note\":\"dlsym_failed\"}"; }
  long msz = mbuf.size();
  long isz = ibuf.size();
  long seq = isz / (768 * 4);
  LOGI("hiai model(buffer): model %ld bytes, input %ld bytes = seq %ld", msz, isz, seq);
  auto t0 = std::chrono::steady_clock::now();
  HIAI_MR_ModelBuildOptions* bopts = api.boptsCreate();
  HIAI_MR_BuiltModel* built = nullptr;
  HIAI_Status st = api.build(bopts, "laya_npu", mbuf.data(), mbuf.size(), &built);
  double buildMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  LOGI("hiai model: build rc=%d, %.0f ms", (int)st, buildMs);
  if (st != HIAI_SUCCESS) {
    return "{\"ok\":0,\"note\":\"build_failed\",\"rc\":" + std::to_string((int)st) +
      ",\"buildMs\":" + std::to_string(buildMs) + "}";
  }
  t0 = std::chrono::steady_clock::now();
  HIAI_MR_ModelManager* mgr = api.mgrCreate();
  HIAI_MR_ModelInitOptions* iopts = api.ioptsCreate();
  st = api.init(mgr, iopts, built, nullptr);
  double initMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  LOGI("hiai model: init rc=%d, %.0f ms", (int)st, initMs);
  if (st != HIAI_SUCCESS) {
    return "{\"ok\":0,\"note\":\"init_failed\",\"rc\":" + std::to_string((int)st) + "}";
  }
  HIAI_NDTensorDesc* inDesc = api.getInDesc(built, 0);
  HIAI_NDTensorDesc* outDesc = api.getOutDesc(built, 0);
  HIAI_MR_NDTensorBuffer* in = api.bufCreate(inDesc);
  HIAI_MR_NDTensorBuffer* out = api.bufCreate(outDesc);
  float* ip = (float*)api.bufData(in);
  memcpy(ip, ibuf.data(), isz);
  HIAI_MR_NDTensorBuffer* tin[1] = {in};
  HIAI_MR_NDTensorBuffer* tout[1] = {out};
  t0 = std::chrono::steady_clock::now();
  st = api.run(mgr, tin, 1, tout, 1);
  double runMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  LOGI("hiai model: run rc=%d, %.0f ms", (int)st, runMs);
  if (st != HIAI_SUCCESS) {
    return "{\"ok\":0,\"note\":\"run_failed\",\"rc\":" + std::to_string((int)st) + "}";
  }
  float* op = (float*)api.bufData(out);
  int nout = api.elementNum(outDesc);
  char vals[256];
  snprintf(vals, sizeof vals, "[%.4f,%.4f,%.4f,%.4f]", op[0], op[1], op[2], op[3]);
  char r[512];
  snprintf(r, sizeof r,
    "{\"ok\":1,\"buildMs\":%.0f,\"initMs\":%.0f,\"runMs\":%.0f,\"seq\":%ld,\"nout\":%d,\"logits\":%s}",
    buildMs, initMs, runMs, seq, nout, vals);
  return r;
}

static void HiaiModelBufferExecute(napi_env env, void* data) {
  auto* j = static_cast<HiaiModelJob*>(data);
  if (j->modelData.size() < 1024) {
    // Tiny payload = run the known-good e2e graph through the buffer path
    // (debugging: isolates buffer-mechanism from model-content issues).
    j->result = run_hiai_e2e();
    return;
  }
  j->result = run_hiai_model_buffer(j->modelData, j->inputData);
}

static void HiaiModelComplete(napi_env env, napi_status status, void* data) {
  auto* j = static_cast<HiaiModelJob*>(data);
  const char* s = (status == napi_ok) ? j->result.c_str() : "";
  napi_value v;
  napi_create_string_utf8(env, s, NAPI_AUTO_LENGTH, &v);
  napi_resolve_deferred(env, j->deferred, v);
  napi_delete_async_work(env, j->work);
  delete j;
}

// Buffer variant: takes the model + input as ArrayBuffers (no file I/O).
static napi_value HiaiModelBuffer(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value a[2];
  napi_get_cb_info(env, info, &argc, a, nullptr, nullptr);
  auto* j = new HiaiModelJob();
  // Keep the ArrayBuffers alive via napi_ref for the async work
  j->modelBuf = nullptr;
  j->inputBuf = nullptr;
  for (size_t k = 0; k < argc && k < 2; k++) {
    void* data = nullptr;
    size_t len = 0;
    bool isBuf = false;
    napi_is_arraybuffer(env, a[k], &isBuf);
    if (isBuf) {
      napi_get_arraybuffer_info(env, a[k], &data, &len);
      if (k == 0) { j->modelData.assign((uint8_t*)data, (uint8_t*)data + len); }
      else { j->inputData.assign((uint8_t*)data, (uint8_t*)data + len); }
    }
  }
  j->modelPath = "buffer";
  j->inputPath = "buffer";
  napi_value p;
  napi_create_promise(env, &j->deferred, &p);
  napi_value nm;
  napi_create_string_utf8(env, "msnnrt.hiaiModelBuffer", NAPI_AUTO_LENGTH, &nm);
  napi_create_async_work(env, nullptr, nm, HiaiModelBufferExecute, HiaiModelComplete, j, &j->work);
  napi_queue_async_work(env, j->work);
  return p;
}

static napi_value HiaiModelTest(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value a[2];
  napi_get_cb_info(env, info, &argc, a, nullptr, nullptr);
  auto* j = new HiaiModelJob();
  for (size_t k = 0; k < argc && k < 2; k++) {
    size_t len = 0;
    napi_get_value_string_utf8(env, a[k], nullptr, 0, &len);
    std::string path;
    path.resize(len);
    napi_get_value_string_utf8(env, a[k], &path[0], len + 1, &len);
    if (k == 0) { j->modelPath = path; } else { j->inputPath = path; }
  }
  napi_value p;
  napi_create_promise(env, &j->deferred, &p);
  napi_value nm;
  napi_create_string_utf8(env, "msnnrt.hiaiModelTest", NAPI_AUTO_LENGTH, &nm);
  napi_create_async_work(env, nullptr, nm, HiaiModelExecute, HiaiModelComplete, j, &j->work);
  napi_queue_async_work(env, j->work);
  return p;
}

// Test whether the app (debug profile, retail) can read from /data/local/tmp/
// — if yes, model files can be pushed there and read by the app.
static napi_value FileReadTest(napi_env env, napi_callback_info info) {
  auto* j = new HiaiJob();
  j->result = "pending";
  napi_value p;
  napi_create_promise(env, &j->deferred, &p);
  napi_value nm;
  napi_create_string_utf8(env, "msnnrt.fileReadTest", NAPI_AUTO_LENGTH, &nm);
  j->work = nullptr;
  // Run synchronously — it's a trivial file read.
  const char* path = "/data/local/tmp/hiai-test.txt";
  FILE* f = fopen(path, "r");
  char buf[64] = {0};
  if (f != nullptr) {
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    j->result = std::string("{\"ok\":1,\"path\":\"/data/local/tmp/hiai-test.txt\",\"read\":") +
      std::to_string(n) + ",\"content\":\"" + buf + "\"}";
  } else {
    j->result = "{\"ok\":0,\"path\":\"/data/local/tmp/hiai-test.txt\",\"errno\":" + std::to_string(errno) + "}";
  }
  // Resolve directly (no async work needed for this).
  napi_value v;
  napi_create_string_utf8(env, j->result.c_str(), NAPI_AUTO_LENGTH, &v);
  napi_resolve_deferred(env, j->deferred, v);
  delete j;
  return p;
}

static napi_value HiaiProbe(napi_env env, napi_callback_info info) {
  auto* j = new HiaiJob();
  j->result = "";
  napi_value p;
  napi_create_promise(env, &j->deferred, &p);
  napi_value nm;
  napi_create_string_utf8(env, "msnnrt.hiaiProbe", NAPI_AUTO_LENGTH, &nm);
  napi_create_async_work(env, nullptr, nm, HiaiExecute, HiaiComplete, j, &j->work);
  napi_queue_async_work(env, j->work);
  return p;
}

/**
 * The HiAI Foundation END-TO-END probe, in-app: build a MatMul graph
 * (Data[1,4] x Const[4,1]) through the stable hiai::I*Def interfaces,
 * serialize it, compile it on-device with HIAI_MR_ModelBuilder_Build, load it
 * with ModelManager and run it. Checks the arithmetic (1+2+3+4 = 10). All
 * entry points are dlsym'd at runtime -- no link-time dependency on the
 * system libs. This is the gate test for the whole NPU path: the shell (uid
 * 0) variant of this flow was rejected by hiaiserver's rpc rule controller
 * ("moduleID:16 not support this uid:0"); whether a real app uid passes is
 * exactly what this decides.
 */
static std::string run_hiai_e2e() {
  void* ir = dlopen("/system/lib64/platformsdk/libhiai_ir.so", RTLD_NOW);
  void* mr = dlopen("/system/lib64/platformsdk/libhiai.so", RTLD_NOW);
  if (ir == nullptr || mr == nullptr) {
    return "{\"ok\":0,\"note\":\"dlopen_failed\"}";
  }
  auto createModelDef = (hiai::IModelDef* (*)())dlsym(ir, "CreateModelDef");
  auto builderBuild =
      (decltype(&HIAI_MR_ModelBuilder_Build))dlsym(mr, "HIAI_MR_ModelBuilder_Build");
  auto buildOptionsCreate = (decltype(&HIAI_MR_ModelBuildOptions_Create))dlsym(
      mr, "HIAI_MR_ModelBuildOptions_Create");
  auto managerCreate =
      (decltype(&HIAI_MR_ModelManager_Create))dlsym(mr, "HIAI_MR_ModelManager_Create");
  auto initOptionsCreate =
      (decltype(&HIAI_MR_ModelInitOptions_Create))dlsym(mr, "HIAI_MR_ModelInitOptions_Create");
  auto managerInit = (decltype(&HIAI_MR_ModelManager_Init))dlsym(mr, "HIAI_MR_ModelManager_Init");
  auto getInputDesc =
      (decltype(&HIAI_MR_BuiltModel_GetInputTensorDesc))dlsym(mr, "HIAI_MR_BuiltModel_GetInputTensorDesc");
  auto getOutputDesc = (decltype(&HIAI_MR_BuiltModel_GetOutputTensorDesc))dlsym(
      mr, "HIAI_MR_BuiltModel_GetOutputTensorDesc");
  auto bufCreate = (decltype(&HIAI_MR_NDTensorBuffer_CreateFromNDTensorDesc))dlsym(
      mr, "HIAI_MR_NDTensorBuffer_CreateFromNDTensorDesc");
  auto bufGetData =
      (decltype(&HIAI_MR_NDTensorBuffer_GetData))dlsym(mr, "HIAI_MR_NDTensorBuffer_GetData");
  auto managerRun = (decltype(&HIAI_MR_ModelManager_Run))dlsym(mr, "HIAI_MR_ModelManager_Run");
  if (createModelDef == nullptr || builderBuild == nullptr ||
      buildOptionsCreate == nullptr || managerCreate == nullptr || initOptionsCreate == nullptr ||
      managerInit == nullptr || getInputDesc == nullptr || getOutputDesc == nullptr ||
      bufCreate == nullptr || bufGetData == nullptr || managerRun == nullptr) {
    return "{\"ok\":0,\"note\":\"dlsym_failed\"}";
  }
  LOGI("hiai e2e: all entry points resolved");

  hiai::IModelDef* model = createModelDef();
  model->set_name("mmmodel");
  hiai::IGraphDef* g = model->add_graph();
  g->set_name("mmgraph");

  hiai::IOpDef* x = g->add_op();
  x->set_name("x");
  x->set_type("Data");
  hiai::ITensorDescDef* xd = x->add_input_desc();
  xd->set_name("x");
  xd->set_dtype(ge::DT_FLOAT);
  xd->mutable_shape()->add_dim(1);
  xd->mutable_shape()->add_dim(4);
  hiai::ITensorDescDef* xo = x->add_output_desc();
  xo->set_name("y");
  xo->set_dtype(ge::DT_FLOAT);
  xo->mutable_shape()->add_dim(1);
  xo->mutable_shape()->add_dim(4);
  g->add_input("x:0");

  hiai::IOpDef* w = g->add_op();
  w->set_name("w");
  w->set_type("Const");
  hiai::IAttrDef* av = w->mutable_attr()->add_attr("value");
  av->SetValueType(ge::AttrValue::VT_TENSOR);
  hiai::ITensorDef* td = av->mutable_t();
  hiai::ITensorDescDef* wd = td->mutable_desc();
  wd->set_dtype(ge::DT_FLOAT);
  wd->mutable_shape()->add_dim(4);
  wd->mutable_shape()->add_dim(1);
  float wdata[4] = {1.f, 2.f, 3.f, 4.f};
  td->set_data(std::string((const char*)wdata, sizeof wdata));
  hiai::ITensorDescDef* wo = w->add_output_desc();
  wo->set_name("y");
  wo->set_dtype(ge::DT_FLOAT);
  wo->mutable_shape()->add_dim(4);
  wo->mutable_shape()->add_dim(1);

  hiai::IOpDef* mm = g->add_op();
  mm->set_name("mm");
  mm->set_type("MatMul");
  mm->add_input("x:0");
  mm->add_input("w:0");
  hiai::ITensorDescDef* mi1 = mm->add_input_desc();
  mi1->set_name("x1");
  mi1->set_dtype(ge::DT_FLOAT);
  mi1->mutable_shape()->add_dim(1);
  mi1->mutable_shape()->add_dim(4);
  hiai::ITensorDescDef* mi2 = mm->add_input_desc();
  mi2->set_name("x2");
  mi2->set_dtype(ge::DT_FLOAT);
  mi2->mutable_shape()->add_dim(4);
  mi2->mutable_shape()->add_dim(1);
  hiai::ITensorDescDef* mo = mm->add_output_desc();
  mo->set_name("y");
  mo->set_dtype(ge::DT_FLOAT);
  mo->mutable_shape()->add_dim(1);
  mo->mutable_shape()->add_dim(1);
  g->add_output("mm:0");
  LOGI("hiai e2e: graph built, %zu ops", g->op_size());

  size_t sz = model->GetModelDefSize();
  std::vector<uint8_t> buf(sz);
  if (!model->SaveTo(buf.data(), sz)) {
    return "{\"ok\":0,\"note\":\"serialize_failed\"}";
  }
  LOGI("hiai e2e: serialized %zu bytes", sz);
  {
    FILE* f = fopen("/data/storage/el2/base/haps/entry/files/e2e-model.pb", "wb");
    if (f != nullptr) { fwrite(buf.data(), 1, sz, f); fclose(f); }
  }

  HIAI_MR_ModelBuildOptions* bopts = buildOptionsCreate();
  HIAI_MR_BuiltModel* built = nullptr;
  HIAI_Status st = builderBuild(bopts, "mmmodel", buf.data(), sz, &built);
  LOGI("hiai e2e: ModelBuilder_Build rc=%d", (int)st);
  if (st != HIAI_SUCCESS) {
    return "{\"ok\":0,\"note\":\"build_failed\",\"rc\":" + std::to_string((int)st) + "}";
  }
  HIAI_MR_ModelManager* mgr = managerCreate();
  HIAI_MR_ModelInitOptions* iopts = initOptionsCreate();
  st = managerInit(mgr, iopts, built, nullptr);
  LOGI("hiai e2e: ModelManager_Init rc=%d", (int)st);
  if (st != HIAI_SUCCESS) {
    return "{\"ok\":0,\"note\":\"init_failed\",\"rc\":" + std::to_string((int)st) + "}";
  }
  HIAI_NDTensorDesc* inDesc = getInputDesc(built, 0);
  HIAI_NDTensorDesc* outDesc = getOutputDesc(built, 0);
  HIAI_MR_NDTensorBuffer* in = bufCreate(inDesc);
  HIAI_MR_NDTensorBuffer* out = bufCreate(outDesc);
  float* ip = (float*)bufGetData(in);
  for (int i = 0; i < 4; i++) { ip[i] = 1.f; }
  HIAI_MR_NDTensorBuffer* tin[1] = {in};
  HIAI_MR_NDTensorBuffer* tout[1] = {out};
  st = managerRun(mgr, tin, 1, tout, 1);
  LOGI("hiai e2e: ModelManager_Run rc=%d", (int)st);
  if (st != HIAI_SUCCESS) {
    return "{\"ok\":0,\"note\":\"run_failed\",\"rc\":" + std::to_string((int)st) + "}";
  }
  float* op = (float*)bufGetData(out);
  char r[160];
  snprintf(r, sizeof r, "{\"ok\":1,\"output\":%.3f,\"expected\":10.0,\"pass\":%s}",
           op[0], (op[0] > 9.5f && op[0] < 10.5f) ? "true" : "false");
  return r;
}

static napi_value Run(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value a[1];
  napi_get_cb_info(env, info, &argc, a, nullptr, nullptr);
  size_t len = 0;
  napi_get_value_string_utf8(env, a[0], nullptr, 0, &len);
  auto* j = new Job();
  j->path.resize(len + 1);
  napi_get_value_string_utf8(env, a[0], &j->path[0], len + 1, &len);
  j->path.resize(len);
  napi_value p;
  napi_create_promise(env, &j->deferred, &p);
  napi_value nm;
  napi_create_string_utf8(env, "msnnrt.run", NAPI_AUTO_LENGTH, &nm);
  napi_create_async_work(env, nullptr, nm, Execute, Complete, j, &j->work);
  napi_queue_async_work(env, j->work);
  return p;
}

static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor d[] = {
    { "run", nullptr, Run, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "hiaiProbe", nullptr, HiaiProbe, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "hiaiE2E", nullptr, HiaiE2E, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "hiaiOps", nullptr, HiaiOps, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "fileReadTest", nullptr, FileReadTest, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "hiaiModelTest", nullptr, HiaiModelTest, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "hiaiModelBuffer", nullptr, HiaiModelBuffer, nullptr, nullptr, nullptr, napi_default, nullptr },
  };
  napi_define_properties(env, exports, sizeof(d) / sizeof(d[0]), d);
  return exports;
}

static napi_module g_msnnrt = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "msnnrt",
    .nm_priv = nullptr,
    .reserved = {0},
};

__attribute__((constructor)) void RegisterMsnnrt(void) { napi_module_register(&g_msnnrt); }