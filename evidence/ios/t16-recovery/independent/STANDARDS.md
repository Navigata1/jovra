# Independent Standards review of bounded recovery prerequisites

Reviewer: root, independently of implementation author review_t02. Pin: dd1cebe10298765a47dc80713fdae3e1b5c3c1d2, including atomic handoff9e64d45a47a329a743a6833af21174a4b812f3cd. Source baseline3ae5caa.

Scope: streaming fragmented-MP4 header boundary checker, public structural/refusal tests, and SessionStore atomic recovered-recording handoff. Read root CLAUDE hard rules, GLOSSARY stats/session language and Apple-only Media/Core boundary. No documented rule breaches or actionable Fowler findings remain in this bounded source.

The header checker reads fixed-size headers with bounded extents and box count; its complete-fragment result explicitly carries no decode claim. Root identified that an O_RDONLY FIFO open could hang before fstat. The author activated the public no-writer FIFO control, confirmed bounded5second blocked invocation, then added O_NONBLOCK. Final3 structural/FIFO controls pass, with2ms FIFO refusal. Earlier launch attempts are honestly unverified. Regular-file refusal now follows an opening mode that does not wait for a named-pipe writer.

The Core actor reuses one synchronous transaction for normal and recovered captures, requires a recovery report for adoption, preserves edited marks/independent facets and fixture provenance, and atomically writes recording/report/original state together. Public out-of-space, reopen and retry checks plus prior capture-handoff regressions substantiate this metadata seam. The test does not claim its referenced synthetic path contains media; scanner verification is still required.

Separate Spec rebind is required before publication. Complete decoded-prefix scanner, stable raw fingerprints/receipt, process-kill loss and physical power-loss criteria remain pending; no fullT16 closure is supported by these prerequisites.
