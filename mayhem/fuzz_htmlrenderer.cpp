// Renders feed-item HTML (TagSoupPullParser -> HtmlRenderer -> TextFormatter), the path every
// article body goes through before display.
#include <clocale>
#include <cstddef>
#include <cstdint>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "htmlrenderer.h"
#include "links.h"
#include "utf8.h"
#include "textformatter.h"

extern "C" int LLVMFuzzerInitialize(int*, char***)
{
	if (!setlocale(LC_CTYPE, "C.UTF-8")) {
		setlocale(LC_CTYPE, "");
	}
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	if (size < 1) {
		return -1;
	}
	// The first byte picks raw mode (links/markup handling off) and the output width (>= 3: render_hr computes width - 2 unsigned).
	const bool raw = data[0] & 1;
	const size_t width = 3 + (data[0] >> 1);
	const std::string html(reinterpret_cast<const char*>(data + 1), size - 1);

	// The library hands strings to Rust (cxx), which aborts on invalid UTF-8; feeds are converted to
	// UTF-8 before they get here, so reject non-UTF-8 input instead of fuzzing that precondition.
	if (!is_valid_utf8(html)) {
		return -1;
	}

	std::vector<std::pair<newsboat::LineType, std::string>> lines;
	newsboat::Links links;
	newsboat::HtmlRenderer renderer(raw);
	renderer.render(html, lines, links, "http://example.com/feed.rss");

	newsboat::TextFormatter formatter(lines);
	formatter.format_text_plain(width);
	return 0;
}
