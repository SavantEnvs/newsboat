// Drives the tag-soup pull parser (HTML/XML tokenizer incl. entity decoding) to the end of input.
#include <clocale>
#include <cstddef>
#include <cstdint>
#include <sstream>
#include <string>

#include "tagsouppullparser.h"
#include "utf8.h"

extern "C" int LLVMFuzzerInitialize(int*, char***)
{
	if (!setlocale(LC_CTYPE, "C.UTF-8")) {
		setlocale(LC_CTYPE, "");
	}
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	// The library hands strings to Rust (cxx), which aborts on invalid UTF-8; feeds are converted to
	// UTF-8 before they get here, so reject non-UTF-8 input instead of fuzzing that precondition.
	const std::string input(reinterpret_cast<const char*>(data), size);
	if (!is_valid_utf8(input)) {
		return -1;
	}
	std::istringstream is(input);
	newsboat::TagSoupPullParser parser(is);
	using Event = newsboat::TagSoupPullParser::Event;
	size_t sink = 0;
	for (Event e = parser.next(); e != Event::END_DOCUMENT; e = parser.next()) {
		sink += parser.get_text().size();
		if (e == Event::START_TAG) {
			sink += parser.get_attribute_value("href").has_value();
			sink += parser.get_attribute_value("src").has_value();
		}
	}
	return sink == static_cast<size_t>(-1);
}
