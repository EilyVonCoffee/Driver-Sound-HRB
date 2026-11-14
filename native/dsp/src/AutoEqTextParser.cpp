#include "iem/AutoEqTextParser.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <iomanip>
#include <regex>
#include <sstream>

namespace iem {
namespace {

bool ParseFloat(const std::string& text, float& value) {
    try {
        std::size_t parsed = 0;
        const auto number = std::stof(text, &parsed);
        if (parsed != text.size() || !std::isfinite(number)) {
            return false;
        }
        value = number;
        return true;
    } catch (...) {
        return false;
    }
}

FilterType ParseType(const std::string& type) {
    std::string upper = type;
    std::transform(upper.begin(), upper.end(), upper.begin(), [](unsigned char value) {
        return static_cast<char>(std::toupper(value));
    });
    if (upper == "LP") return FilterType::LowPass;
    if (upper == "HP") return FilterType::HighPass;
    if (upper == "LS") return FilterType::LowShelf;
    if (upper == "HS") return FilterType::HighShelf;
    return FilterType::Peaking;
}

const char* TypeName(FilterType type) {
    switch (type) {
        case FilterType::LowPass: return "LP";
        case FilterType::HighPass: return "HP";
        case FilterType::LowShelf: return "LS";
        case FilterType::HighShelf: return "HS";
        case FilterType::Peaking: return "PK";
    }
    return "PK";
}

}  // namespace

ParseResult ParseAutoEqText(const std::string& text) {
    static const std::regex preampPattern(
        R"(^\s*Preamp\s*:\s*([-+0-9.eE]+)\s*dB\s*$)", std::regex::icase);
    static const std::regex filterPattern(
        R"(^\s*Filter\s+(\d+)\s*:\s*(ON|OFF)\s+(PK|LP|HP|LS|HS)\s+Fc\s+([-+0-9.eE]+)\s*Hz\s+Gain\s+([-+0-9.eE]+)\s*dB\s+Q\s+([-+0-9.eE]+)\s*$)",
        std::regex::icase);

    ParseResult result{};
    std::istringstream lines(text);
    std::string line;
    std::size_t lineNumber = 0;
    bool sawDirective = false;

    while (std::getline(lines, line)) {
        ++lineNumber;
        std::smatch match;
        if (std::regex_match(line, match, preampPattern)) {
            float value = 0.0F;
            if (!ParseFloat(match[1].str(), value)) {
                result.issues.push_back({lineNumber, "Invalid preamp value"});
            } else {
                result.configuration.preampDb = value;
                sawDirective = true;
            }
            continue;
        }
        if (!std::regex_match(line, match, filterPattern)) {
            continue;
        }

        std::size_t filterIndex = 0;
        try {
            filterIndex = static_cast<std::size_t>(std::stoul(match[1].str()));
        } catch (...) {
            result.issues.push_back({lineNumber, "Invalid filter index"});
            continue;
        }
        if (filterIndex == 0U || filterIndex > kEqBandCount) {
            result.issues.push_back({lineNumber, "Filter index must be from 1 to 10"});
            continue;
        }

        BandParameters band{};
        auto enabledText = match[2].str();
        std::transform(enabledText.begin(), enabledText.end(), enabledText.begin(), [](unsigned char value) {
            return static_cast<char>(std::toupper(value));
        });
        band.enabled = enabledText == "ON";
        band.type = ParseType(match[3].str());
        if (!ParseFloat(match[4].str(), band.frequencyHz) ||
            !ParseFloat(match[5].str(), band.gainDb) ||
            !ParseFloat(match[6].str(), band.q)) {
            result.issues.push_back({lineNumber, "Invalid filter parameter"});
            continue;
        }
        result.configuration.bands[filterIndex - 1U] = band;
        sawDirective = true;
    }

    result.success = sawDirective && result.issues.empty();
    return result;
}

std::string ExportAutoEqText(const EqConfiguration& configuration) {
    std::ostringstream output;
    output << std::fixed << std::setprecision(2)
           << "Preamp: " << configuration.preampDb << " dB\n";
    for (std::size_t i = 0; i < kEqBandCount; ++i) {
        const auto& band = configuration.bands[i];
        output << "Filter " << (i + 1U) << ": " << (band.enabled ? "ON" : "OFF")
               << ' ' << TypeName(band.type)
               << " Fc " << band.frequencyHz << " Hz"
               << " Gain " << band.gainDb << " dB"
               << " Q " << band.q << '\n';
    }
    return output.str();
}

}  // namespace iem
