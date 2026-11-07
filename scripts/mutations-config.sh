# The mutations of Roxie.Config, sourced by scripts/in-gate.sh.
mutations+=(
	"Config.hiq|s/constant filesMost: Index := 64;/constant filesMost: Index := 65;/|65 files"
	"Config.hiq|s/constant everyMost: Int64 := 3600;/constant everyMost: Int64 := 3601;/|every 3601"
	"Config.hiq|s/                    if (seconds < 1) or (seconds > everyMost) then/                    if seconds > everyMost then/|every 0"
	"Config.hiq|s/        return value\[0\] = '\/';/        return true;/|a relative path"
	"Config.hiq|s/                    if not isCollector(value) then/                    if false then/|a collector that is no https URL"
	"Config.hiq|s/                    if everyLine > 0 then/                    if false then/|every twice"
	"Config.hiq|s/ or (text\[stop - 1\] = 13)) do/ or false) do/|a carriage return kept in a value"
	"Config.hiq|s/                let complete: Bool := .*;/                let complete: Bool := true;/|a setting missing"
	"Config.hiq|s/                let complete: Bool := reached and (present(found.certificate) and present(found.key));/                let complete: Bool := reached and present(found.certificate);/|an agent without its key"
	"Config.hiq|s/                let complete: Bool := reached and (present(found.certificate) and present(found.key));/                let complete: Bool := reached;/|an agent without its certificate"
	"Config.hiq|s/constant reportMost: Int64 := 86400;/constant reportMost: Int64 := 86401;/|report 86401"
	"Config.hiq|s/                    if (quiet < 0) or (quiet > reportMost) then/                    if quiet > reportMost then/|report below 0"
	"Config.hiq|s/                    if reportLine > 0 then/                    if false then/|report twice"
	"Config.hiq|s/        var report: Int64 := reportUsual;/        var report: Int64 := 0;/|no report says every round"
	"Config.hiq|s/                    if spanLength(value) <= 5 then/                    if spanLength(value) <= 7 then/|report of seven digits"
)
