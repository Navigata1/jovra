# AC5: grep -inw <module> spec/studio/README.md for every module page (expected: no line)
$ grep -inw bundle spec/studio/README.md
(no match)
[exit 1]
$ grep -inw core spec/studio/README.md
(no match)
[exit 1]
$ grep -inw edl spec/studio/README.md
(no match)
[exit 1]
$ grep -inw jobstate spec/studio/README.md
(no match)
[exit 1]
$ grep -inw ledger spec/studio/README.md
(no match)
[exit 1]
$ grep -inw normalization spec/studio/README.md
(no match)
[exit 1]
$ grep -inw records spec/studio/README.md
(no match)
[exit 1]
$ grep -inw sync spec/studio/README.md
(no match)
[exit 1]
$ grep -n modules/README.md spec/studio/README.md   # the link to the generated index
41:`spec/studio/modules/`, linked from the generated index [`modules/README.md`](modules/README.md). This README holds
