use std::ptr;

use crate::error::FfiError;

/// Borrowed C byte slice.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct KshiftSlice {
    pub data: *const u8,
    pub len: usize,
}

/// Owned C byte buffer.
#[repr(C)]
pub struct KshiftBuffer {
    pub data: *mut u8,
    pub len: usize,
    pub capacity: usize,
}

impl KshiftBuffer {
    pub const EMPTY: Self = Self {
        data: ptr::null_mut(),
        len: 0,
        capacity: 0,
    };
}

pub unsafe fn copy_slice(
    slice: KshiftSlice,
    field: &'static str,
    max_bytes: usize,
) -> Result<Vec<u8>, FfiError> {
    if slice.len > max_bytes {
        return Err(FfiError::MessageTooLarge {
            field,
            actual: slice.len,
            limit: max_bytes,
        });
    }
    if slice.len == 0 {
        return Ok(Vec::new());
    }
    if slice.data.is_null() {
        return Err(FfiError::InvalidArgument(format!(
            "{field}.data is null while len is non-zero"
        )));
    }
    Ok(std::slice::from_raw_parts(slice.data, slice.len).to_vec())
}

pub unsafe fn write_buffer(bytes: Vec<u8>, output: *mut KshiftBuffer) -> Result<(), FfiError> {
    if output.is_null() {
        return Err(FfiError::InvalidArgument(
            "output buffer pointer is null".to_owned(),
        ));
    }
    if bytes.is_empty() {
        output.write(KshiftBuffer::EMPTY);
        return Ok(());
    }
    let boxed = bytes.into_boxed_slice();
    let len = boxed.len();
    let data = Box::into_raw(boxed).cast::<u8>();
    output.write(KshiftBuffer {
        data,
        len,
        capacity: len,
    });
    Ok(())
}

pub unsafe fn free_buffer(buffer: *mut KshiftBuffer) -> Result<(), FfiError> {
    if buffer.is_null() {
        return Err(FfiError::InvalidArgument(
            "buffer pointer is null".to_owned(),
        ));
    }
    let current = ptr::read(buffer);
    if current.data.is_null() {
        buffer.write(KshiftBuffer::EMPTY);
        return Ok(());
    }
    if current.len == 0 || current.capacity != current.len {
        return Err(FfiError::InvalidArgument(
            "buffer length and capacity are inconsistent".to_owned(),
        ));
    }
    buffer.write(KshiftBuffer::EMPTY);
    let slice = ptr::slice_from_raw_parts_mut(current.data, current.len);
    drop(Box::from_raw(slice));
    Ok(())
}
