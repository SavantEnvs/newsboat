// Parses a filter expression ("title =~ \"x\" and unread = \"yes\"") and evaluates it against an item.
#include <cstddef>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>

#include <fuzzer/FuzzedDataProvider.h>

#include "matchable.h"
#include "matcher.h"
#include "matcherexception.h"

namespace {
// Answers attribute lookups with one of a few fuzzer-chosen values (or none), keyed by attribute name.
class FuzzMatchable : public newsboat::Matchable {
public:
	explicit FuzzMatchable(FuzzedDataProvider& fdp)
		: values{fdp.ConsumeRandomLengthString(40), fdp.ConsumeRandomLengthString(40),
			fdp.ConsumeRandomLengthString(40)}
	{
	}

	std::optional<std::string> attribute_value(const std::string& attr) const override
	{
		const size_t slot = std::hash<std::string> {}(attr) % 4;
		if (slot == 3) {
			return std::nullopt;
		}
		return values[slot];
	}

private:
	std::string values[3];
};
} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	FuzzedDataProvider fdp(data, size);
	FuzzMatchable item(fdp);
	const std::string expr = fdp.ConsumeRemainingBytesAsString();

	// The Coco/R scanner calls exit(1) on a leading 0xEF that isn't a UTF-8 BOM, and on any token over
	// 16k characters (its 64 KiB token heap). Reject those inputs rather than fuzz an exit().
	if (expr.size() > 8192 || (!expr.empty() && static_cast<uint8_t>(expr[0]) == 0xEF)) {
		return -1;
	}

	newsboat::Matcher matcher;
	if (!matcher.parse(expr)) {
		return 0;
	}
	matcher.get_referenced_attributes();
	// Unknown attributes and bad regexes are reported as MatcherException; that is the documented error path.
	try {
		matcher.matches(&item);
	} catch (const newsboat::MatcherException&) {
	}
	return 0;
}
