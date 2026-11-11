// Wraps and renders a list of typed lines (wrappable / softwrappable / nonwrappable / hr) at fuzzer-chosen widths.
#include <clocale>
#include <cstddef>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

#include <fuzzer/FuzzedDataProvider.h>

#include "textformatter.h"
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
	FuzzedDataProvider fdp(data, size);
	const size_t wrap_width = fdp.ConsumeIntegralInRange<size_t>(3, 200);
	const size_t total_width = fdp.ConsumeIntegralInRange<size_t>(0, 200);

	std::vector<std::pair<newsboat::LineType, std::string>> lines;
	while (fdp.remaining_bytes() > 0) {
		const auto type = static_cast<newsboat::LineType>(fdp.ConsumeIntegralInRange<int>(1, 4));
		std::string text = fdp.ConsumeRandomLengthString(120);
		// The library hands strings to Rust (cxx), which aborts on invalid UTF-8; feeds are converted to
		// UTF-8 before they get here, so reject non-UTF-8 input instead of fuzzing that precondition.
		if (!is_valid_utf8(text)) {
			return -1;
		}
		lines.emplace_back(type, std::move(text));
	}

	newsboat::TextFormatter formatter(lines);
	formatter.format_text_plain(wrap_width, total_width);
	formatter.format_text_to_list(nullptr, {}, wrap_width, total_width);
	return 0;
}
