# normalize-pwd-case.fish -- keep $PWD spelled exactly like the on-disk entry
# names. On case-insensitive APFS a cd through a wrong-case path succeeds, fish
# keeps the typed spelling in $PWD, and that string then leaks to every child
# process and to new terminal tabs (shell integration reports $PWD; the new tab
# starts there and inherits the casing) -- feeding case-sensitive byte compares
# downstream. Correct it at the source: after every PWD change, walk the path
# component by component against the parent directory's real entries and re-cd
# through the corrected spelling. cd re-sets $PWD itself.
#
# CASE-ONLY: a component is only replaced by a directory entry matching it
# case-insensitively, and an exact-case entry always wins (on a case-SENSITIVE
# volume both spellings can exist; never rewrite then). Symlink components are
# corrected by NAME, never resolved -- path identity stays logical. Ambiguous,
# unmatched, or failed: keep the typed path. Companion to the claude-shim's
# launch-boundary normalization (claude-code-hardening e1d300f), which still
# covers launches from other shells.

function __normalize_pwd_case --on-variable PWD
    set -l typed $PWD
    string match -q '/*' -- $typed; or return 0
    set -l fixed ""
    for comp in (string split -n / -- $typed)
        set -l cand
        set -l lcomp (string lower -- $comp)
        for entry in $fixed/* $fixed/.*
            set -l name (path basename -- $entry)
            if test "$name" = "$comp"
                # exact-case entry: always wins, keep typed
                set cand $comp
                break
            end
            if test (string lower -- $name) = "$lcomp"
                set -a cand $name
            end
        end
        if test (count $cand) -eq 1
            set fixed "$fixed/$cand[1]"
        else
            # unmatched or ambiguous: keep the typed spelling
            set fixed "$fixed/$comp"
        end
    end
    test -n "$fixed"; or set fixed /
    if test "$fixed" != "$typed"
        # same directory only (device+inode compare), then re-cd through the
        # corrected spelling. builtin cd: no cd-history churn, and the handler
        # re-fires once with fixed == typed and stops.
        if test -d "$fixed"; and test "$fixed" -ef "$typed"
            builtin cd $fixed
        end
    end
end

# Startup cwd: the handler only fires on changes, but a wrong-case $PWD can be
# inherited from the spawning environment (terminal tab inheritance).
__normalize_pwd_case
