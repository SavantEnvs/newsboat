// Strict UTF-8 validation (no overlongs, surrogates or > U+10FFFF), matching what Rust's str requires.
#pragma once
#include <cstddef>
#include <cstdint>
#include <string>

inline bool is_valid_utf8(const std::string& s)
{
	const auto* p = reinterpret_cast<const uint8_t*>(s.data());
	const size_t n = s.size();
	size_t i = 0;
	while (i < n) {
		const uint8_t c = p[i];
		size_t len;
		uint32_t cp;
		if (c < 0x80) {
			i++;
			continue;
		} else if (c >= 0xC2 && c <= 0xDF) {
			len = 2;
			cp = c & 0x1F;
		} else if (c >= 0xE0 && c <= 0xEF) {
			len = 3;
			cp = c & 0x0F;
		} else if (c >= 0xF0 && c <= 0xF4) {
			len = 4;
			cp = c & 0x07;
		} else {
			return false;
		}
		if (i + len > n) {
			return false;
		}
		for (size_t k = 1; k < len; k++) {
			if ((p[i + k] & 0xC0) != 0x80) {
				return false;
			}
			cp = (cp << 6) | (p[i + k] & 0x3F);
		}
		if ((len == 3 && cp < 0x800) || (len == 4 && cp < 0x10000) || cp > 0x10FFFF ||
			(cp >= 0xD800 && cp <= 0xDFFF)) {
			return false;
		}
		i += len;
	}
	return true;
}
