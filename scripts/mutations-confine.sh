# The mutations of Roxie.Confine, sourced by scripts/in-gate.sh.
mutations+=(
	"Confine.hiq|s/        return \"stdio rpath wpath cpath flock inet dns\";/        return \"stdio rpath wpath cpath inet dns\";/|no flock for SQLite's locks"
	"Confine.hiq|s/            if (length(\&place) > 1) and (not directoryBefore(files, i, asSpan(\&place))) then/            if length(\&place) > 1 then/|a directory granted twice"
	"Confine.hiq|s/            if (length(\&place) > 1) and (not directoryBefore(files, i, asSpan(\&place))) then/            if true then/|the root granted for a file under it"
	"Confine.hiq|s/        if length(\&directory) > 1 then/        if true then/|the root granted for a state under it"
	"Confine.hiq|s/            policy := allowPath(policy, asSpan(\&directory), \"rwc\");/            policy := allowPath(policy, asSpan(\&directory), \"rw\");/|no journal may be created beside the state"
	"Confine.hiq|s/                policy := allowPath(policy, asSpan(\&place), \"r\");/                policy := allowPath(policy, asSpan(nthRef(files, i)), \"r\");/|the file and not its directory"
	"Confine.hiq|s/        policy := allowPath(policy, asSpan(\&(config->key)), \"r\");//|the key out of reach"
	"Confine.hiq|s/        policy := allowPath(policy, \"\/etc\/hosts\", \"r\");//|no hosts file"
)
