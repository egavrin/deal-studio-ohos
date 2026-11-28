//! The HiAI Foundation runtime forward for the Laya batched serving graph.
//!
//! The graph (tools/local-jev/hiai-gen.py --batched B) is a fixed-shape
//! model: B question slots, each padded to the fixed `seq`. It takes three
//! inputs in declaration order -- the raw token embeddings [B*seq, 768], the
//! padding mask [B, seq, seq] and the type-embedding addend [B*seq, 768] --
//! and returns the hidden states [B*seq, 768] after the encoder, the final
//! norm, the type add and the two head layers. The host (the Rust engine)
//! does the tokenizer, the embedding lookup, the type add and the marker
//! scorer; this module replaces only the candle forward.
//!
//! All entry points are dlopen'd from /system/lib64/platformsdk/libhiai.so:
//! no link-time dependency, and a missing library degrades to the CPU path.

use std::ffi::CString;
use std::path::Path;

type CStatus = i32;
type CBool = i32;

#[repr(C)]
struct CTensorDesc;
#[repr(C)]
struct CTensorBuffer;
#[repr(C)]
struct BuildOptions;
#[repr(C)]
struct InitOptions;
#[repr(C)]
struct ModelManager;
#[repr(C)]
struct BuiltModel;

const HIAI_OK: CStatus = 0;

macro_rules! sym {
    ($lib:expr, $name:literal, $ty:ty) => {{
        let ptr = libc::dlsym($lib, concat!($name, "\0").as_ptr() as *const libc::c_char);
        if ptr.is_null() {
            None
        } else {
            Some(core::mem::transmute::<*mut core::ffi::c_void, $ty>(ptr))
        }
    }};
}

pub struct NpuForward {
    #[allow(dead_code)]
    lib: *mut libc::c_void,
    bopts_create: unsafe extern "C" fn() -> *mut BuildOptions,
    iopts_create: unsafe extern "C" fn() -> *mut InitOptions,
    mgr_create: unsafe extern "C" fn() -> *mut ModelManager,
    build: unsafe extern "C" fn(*const BuildOptions, *const i8, *const u8, usize, *mut *mut BuiltModel) -> CStatus,
    init: unsafe extern "C" fn(*mut ModelManager, *const InitOptions, *const BuiltModel, *const ()) -> CStatus,
    get_in_desc: unsafe extern "C" fn(*const BuiltModel, usize) -> *mut CTensorDesc,
    get_out_desc: unsafe extern "C" fn(*const BuiltModel, usize) -> *mut CTensorDesc,
    buf_create: unsafe extern "C" fn(*const CTensorDesc) -> *mut CTensorBuffer,
    buf_data: unsafe extern "C" fn(*const CTensorBuffer) -> *mut core::ffi::c_void,
    element_num: unsafe extern "C" fn(*const CTensorDesc) -> usize,
    run: unsafe extern "C" fn(*mut ModelManager, *mut *mut CTensorBuffer, i32, *mut *mut CTensorBuffer, i32) -> CStatus,
    save_to_file: Option<unsafe extern "C" fn(*const BuiltModel, *const i8) -> CStatus>,
    restore_from_file: Option<unsafe extern "C" fn(*const i8) -> *mut BuiltModel>,
    built: *mut BuiltModel,
    mgr: *mut ModelManager,
    inputs: Vec<*mut CTensorBuffer>,
    output: *mut CTensorBuffer,
    pub batch: usize,
    pub seq: usize,
    pub dim: usize,
}

// The tensors are owned by the model manager's lifetime; Send is safe: all
// calls are serialized by the engine mutex.
unsafe impl Send for NpuForward {}

impl NpuForward {
    /// Load the graph bytes and compile once. `None` on any failure: the
    /// caller falls back to the candle CPU path.
    pub fn try_new(model_path: &Path, batch: usize, seq: usize, dim: usize) -> Option<Self> {
        let bytes = std::fs::read(model_path).ok()?;
        let name = CString::new("laya_npu").ok()?;
        unsafe {
            let lib = libc::dlopen(
                b"/system/lib64/platformsdk/libhiai.so\0".as_ptr() as *const libc::c_char,
                libc::RTLD_NOW,
            );
            if lib.is_null() {
                return None;
            }
            let bopts_create = sym!(lib, "HIAI_MR_ModelBuildOptions_Create", unsafe extern "C" fn() -> *mut BuildOptions)?;
            let iopts_create = sym!(lib, "HIAI_MR_ModelInitOptions_Create", unsafe extern "C" fn() -> *mut InitOptions)?;
            let mgr_create = sym!(lib, "HIAI_MR_ModelManager_Create", unsafe extern "C" fn() -> *mut ModelManager)?;
            let build = sym!(lib, "HIAI_MR_ModelBuilder_Build", unsafe extern "C" fn(*const BuildOptions, *const i8, *const u8, usize, *mut *mut BuiltModel) -> CStatus)?;
            let init = sym!(lib, "HIAI_MR_ModelManager_Init", unsafe extern "C" fn(*mut ModelManager, *const InitOptions, *const BuiltModel, *const ()) -> CStatus)?;
            let get_in_desc = sym!(lib, "HIAI_MR_BuiltModel_GetInputTensorDesc", unsafe extern "C" fn(*const BuiltModel, usize) -> *mut CTensorDesc)?;
            let get_out_desc = sym!(lib, "HIAI_MR_BuiltModel_GetOutputTensorDesc", unsafe extern "C" fn(*const BuiltModel, usize) -> *mut CTensorDesc)?;
            let buf_create = sym!(lib, "HIAI_MR_NDTensorBuffer_CreateFromNDTensorDesc", unsafe extern "C" fn(*const CTensorDesc) -> *mut CTensorBuffer)?;
            let buf_data = sym!(lib, "HIAI_MR_NDTensorBuffer_GetData", unsafe extern "C" fn(*const CTensorBuffer) -> *mut core::ffi::c_void)?;
            let element_num = sym!(lib, "HIAI_NDTensorDesc_GetTotalDimNum", unsafe extern "C" fn(*const CTensorDesc) -> usize)?;
            let run = sym!(lib, "HIAI_MR_ModelManager_Run", unsafe extern "C" fn(*mut ModelManager, *mut *mut CTensorBuffer, i32, *mut *mut CTensorBuffer, i32) -> CStatus)?;

            let save_to_file = sym!(lib, "HIAI_MR_BuiltModel_SaveToFile", unsafe extern "C" fn(*const BuiltModel, *const i8) -> CStatus);
            let restore_from_file = sym!(lib, "HIAI_MR_BuiltModel_RestoreFromFile", unsafe extern "C" fn(*const i8) -> *mut BuiltModel);
            // Model persistence: a previously-compiled model skips the
            // on-device compile. The cache file lives beside the graph.
            let cache = model_path.with_extension("compiled");
            let mut built: *mut BuiltModel = core::ptr::null_mut();
            if let Some(restore) = restore_from_file {
                if let Ok(cname) = CString::new(cache.to_string_lossy().as_bytes().to_vec()) {
                    let restored = restore(cname.as_ptr() as *const i8);
                    if !restored.is_null() {
                        built = restored;
                    }
                }
            }
            if built.is_null() {
                let bopts = bopts_create();
                if build(bopts, name.as_ptr() as *const i8, bytes.as_ptr(), bytes.len(), &mut built) != HIAI_OK {
                    return None;
                }
                // Save the compiled form so the next cold start skips the build.
                if let Some(save) = save_to_file {
                    if let Ok(cname) = CString::new(cache.to_string_lossy().as_bytes().to_vec()) {
                        let _ = save(built, cname.as_ptr() as *const i8);
                    }
                }
            }
            let mgr = mgr_create();
            let iopts = iopts_create();
            if init(mgr, iopts, built, core::ptr::null()) != HIAI_OK {
                return None;
            }
            // Three inputs in declaration order: emb, pmask, tadd.
            let mut inputs = Vec::new();
            for k in 0..3 {
                let desc = get_in_desc(built, k);
                if desc.is_null() {
                    return None;
                }
                let buf = buf_create(desc);
                if buf.is_null() {
                    return None;
                }
                inputs.push(buf);
            }
            let out_desc = get_out_desc(built, 0);
            if out_desc.is_null() {
                return None;
            }
            let output = buf_create(out_desc);
            if output.is_null() {
                return None;
            }
            let n_out = element_num(out_desc);
            if n_out != batch * seq * dim {
                return None;
            }
            Some(NpuForward {
                lib, bopts_create, iopts_create, mgr_create, build, init,
                get_in_desc, get_out_desc, buf_create, buf_data, element_num, run,
                save_to_file, restore_from_file,
                built, mgr, inputs, output, batch, seq, dim,
            })
        }
    }

    /// One forward: the three inputs and the output are already-sized
    /// buffers (slice lengths are validated). Returns the hidden states
    /// [batch*seq, dim] or None on failure (the caller falls back).
    pub fn forward(&self, emb: &[f32], pmask: &[f32], tadd: &[f32]) -> Option<Vec<f32>> {
        let bs = self.batch * self.seq;
        if emb.len() != bs * self.dim || tadd.len() != bs * self.dim {
            return None;
        }
        if pmask.len() != self.batch * self.seq * self.seq {
            return None;
        }
        unsafe {
            let dsts = [(self.buf_data)(self.inputs[0]), (self.buf_data)(self.inputs[1]), (self.buf_data)(self.inputs[2])];
            core::ptr::copy_nonoverlapping(emb.as_ptr(), dsts[0] as *mut f32, emb.len());
            core::ptr::copy_nonoverlapping(pmask.as_ptr(), dsts[1] as *mut f32, pmask.len());
            core::ptr::copy_nonoverlapping(tadd.as_ptr(), dsts[2] as *mut f32, tadd.len());
            let mut tin = [self.inputs[0], self.inputs[1], self.inputs[2]];
            let mut tout = [self.output];
            if (self.run)(self.mgr, tin.as_mut_ptr(), tin.len() as i32, tout.as_mut_ptr(), 1) != HIAI_OK {
                return None;
            }
            let out_ptr = (self.buf_data)(self.output) as *const f32;
            let n = bs * self.dim;
            Some(core::slice::from_raw_parts(out_ptr, n).to_vec())
        }
    }
}

impl Drop for NpuForward {
    fn drop(&mut self) {
        // The buffers and models are owned by the process-wide runtime; the
        // drop is best-effort (no destroy symbols were needed for probing).
        unsafe {
            libc::dlclose(self.lib);
        }
    }
}
