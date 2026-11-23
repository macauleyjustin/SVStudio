#ifndef CZLIB_H
#define CZLIB_H

#include <zlib.h>
#include <stdint.h>
#include <stdlib.h>

static inline int sat_inflate_raw(
    const uint8_t *src, size_t src_len,
    uint8_t *dst, size_t dst_cap,
    size_t *out_len
) {
    z_stream strm;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    strm.avail_in = (uInt)src_len;
    strm.next_in = (Bytef *)src;
    if (inflateInit2(&strm, -MAX_WBITS) != Z_OK) {
        return -1;
    }
    strm.avail_out = (uInt)dst_cap;
    strm.next_out = (Bytef *)dst;
    int ret = inflate(&strm, Z_FINISH);
    *out_len = (size_t)strm.total_out;
    inflateEnd(&strm);
    return (ret == Z_STREAM_END) ? 0 : ret;
}

static inline int sat_deflate_raw(
    const uint8_t *src, size_t src_len,
    uint8_t *dst, size_t dst_cap,
    size_t *out_len
) {
    z_stream strm;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return -1;
    }
    strm.avail_in = (uInt)src_len;
    strm.next_in = (Bytef *)src;
    strm.avail_out = (uInt)dst_cap;
    strm.next_out = (Bytef *)dst;
    int ret = deflate(&strm, Z_FINISH);
    *out_len = (size_t)strm.total_out;
    deflateEnd(&strm);
    return (ret == Z_STREAM_END) ? 0 : ret;
}

static inline uint32_t sat_crc32(const uint8_t *src, size_t len) {
    return (uint32_t)crc32(0L, src, (uInt)len);
}

#endif
