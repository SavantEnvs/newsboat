// Parses a feed document (RSS 0.9x/1.0/2.0, Atom) through rsspp::Parser over libxml2.
#include <clocale>
#include <cstddef>
#include <cstdint>
#include <string>

#include "rss/exception.h"
#include "rss/parser.h"

extern "C" int LLVMFuzzerInitialize(int*, char***)
{
	if (!setlocale(LC_CTYPE, "C.UTF-8")) {
		setlocale(LC_CTYPE, "");
	}
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	rsspp::Parser parser;
	try {
		const auto feed = parser.parse_buffer(
				std::string(reinterpret_cast<const char*>(data), size));
		return feed.items.size() == static_cast<size_t>(-1);
	} catch (const rsspp::Exception&) {
		return 0;
	}
}
