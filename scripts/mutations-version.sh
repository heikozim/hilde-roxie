# The mutations of Roxie.Version, sourced by scripts/in-gate.sh.
mutations+=(
	"Version.hiq|s/            if version\[0\] = 118 then/            if false then/|the v of a tag kept"
	"Version.hiq|s/            if text\[i\] = 45 then/            if false then/|the commits after the tag kept"
	"Version.hiq|s/        return (byte = 46) or (byte = 45) or (byte = 43);/        return true;/|any byte in a version"
	"Version.hiq|s/        return (byte = 46) or (byte = 45) or (byte = 43);/        return (byte = 46) or (byte = 45);/|no plus in a version"
	"Version.hiq|s/        if not isDigit(version\[first\]) then/        if false then/|a version without a digit first"
	"Version.hiq|s/            if not versionByte(version\[i\]) then/            if false then/|a version of odd bytes"
	"Version.hiq|s/        if (byte >= 97) and (byte <= 122) then/        if (byte >= 97) and (byte <= 121) then/|no z in a version"
	"Version.hiq|s/                return \"dev\";/                return \"\";/|no dev for a build without a version"
)
