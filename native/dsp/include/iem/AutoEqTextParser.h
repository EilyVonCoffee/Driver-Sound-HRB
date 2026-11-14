#pragma once

#include "iem/ParametricEq.h"

#include <string>
#include <vector>

namespace iem {

struct ParseIssue {
    std::size_t line{0};
    std::string message;
};

struct ParseResult {
    EqConfiguration configuration{};
    std::vector<ParseIssue> issues;
    bool success{false};
};

ParseResult ParseAutoEqText(const std::string& text);
std::string ExportAutoEqText(const EqConfiguration& configuration);

}  // namespace iem
