# The mutations of Roxie.Web, sourced by scripts/in-gate.sh.
mutations+=(
	"Web.hiq|s/constant sizeOfPage: Int64 := 50;/constant sizeOfPage: Int64 := 51;/|51 lines a page"
	"Web.hiq|s/                        if (offset + count) < total then/                        if (offset + count) <= total then/|a link past the last page"
	"Web.hiq|s/                            newer := offset - sizeOfPage;/                            newer := offset;/|the newer page is the same page"
	"Web.hiq|s/                return \"a value the field does not take\";/                return \"bad\";/|a problem without its words"
	"Web.hiq|s/            if text\[stop - 1\] = 10 then/            if false then/|the line end of a line kept"
	"Web.hiq|s/                return timeText(seconds);/                return fromSpan(\"\");/|a line without its time"
	"Web.hiq|s/        insertBack(\&!panels, panelOf(\"refused\", \(.*\)));/        let skipped: Panel := panelOf(\"refused\", \1);/|a panel missing"
	"Web.hiq|s/csrf => fromSpan(csrf));/csrf => fromSpan(\"\"));/|the head without the form token"
	"Web.hiq|s/        if spanLength(text) = 0 then/        if false then/|an empty query searched"
	#: the panels of the hosts.
	"Web.hiq|s/withInt64(noValues(), now - hostsWindow)/withInt64(noValues(), (now - hostsWindow) - 1)/|a line older than 24 hours counts"
	"Web.hiq|s/constant hostsWindow: Int64 := 86400;/constant hostsWindow: Int64 := 86399;/|the line of 24 hours ago is left out"
	"Web.hiq|s/        let first: Bool := columnInt64(cursor, 9) = 1;/        let first: Bool := true;/|every row opens a section"
	"Web.hiq|s/        let closes: Bool := columnInt64(cursor, 10) = 1;/        let closes: Bool := false;/|a host's section is never closed"
	"Web.hiq|s/row_number() OVER (PARTITION BY host ORDER BY source DESC)/row_number() OVER (PARTITION BY host ORDER BY source)/|the first source closes the section"
	"Web.hiq|s/sum(sum(level = 'error')) OVER byHost/sum(sum(level = 'warn')) OVER byHost/|the host's warnings as its errors"
	"Web.hiq|s/ORDER BY host, source LIMIT 500/ORDER BY host DESC, source LIMIT 500/|the hosts out of order"
	#: the foot of every page.
	"Web.hiq|s/                writeString(\&!out, foot);/                writeString(\&!out, \"\");/|the foot left out"
	"Web.hiq|s/        case indexOf(page, \"<\/body>\") of/        case indexOf(page, \"<\/html>\") of/|the foot after the end of the body"
	"Web.hiq|s/ - (c) 2026 <a href=/ - (c) 2025 <a href=/|another year"
)
