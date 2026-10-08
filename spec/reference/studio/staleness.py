"""Staleness propagation (SD20): which plans and films a revision bump makes stale.

Standard library only. A project has three revisions a plan depends on: the event revision (the point-event log), the
sync revision and the keeper-catalog revision. `propagate(state, changes)` applies revision bumps in order and returns
every plan and film with its status:

- an **event** bump stales every plan of that project bound to the older event revision (a plan's scores, stats and
  keeper windows all come from the whole fold, so no plan of the project is exempt);
- a **sync** bump names the sources whose mapping changed; it stales only the plans that cut or play one of them, and
  the other plans are rebound to the new sync revision;
- a **keeper** bump names the keepers that changed; it stales only the plans that use one of them, and the other plans
  are rebound to the new keeper-catalog revision.

A film is stale when the plan it was rendered from (by canonical edit-plan hash) is stale; it is labelled "Made before a
correction" and kept as a version, never deleted or silently re-rendered. Module page: spec/studio/modules/keepers.md.
"""

from __future__ import annotations

import copy

from studio.core import Reject, canonical_sha256, require

FILM_LABEL = "Made before a correction"
KINDS = {"event": ("eventRevision", "event-revision"), "sync": ("syncRevision", "sync-revision"),
         "keepers": ("keeperCatalogRevision", "keeper-revision")}
BINDINGS = ("eventRevision", "syncRevision", "keeperCatalogRevision")
REASON_ORDER = ("event-revision", "sync-revision", "keeper-revision")


def plan_dependencies(plan: dict) -> dict:
    """What a stored edit plan (jovra.edit-plan/2) depends on: its bound revisions, every source a segment or the audio
    bed uses, and every keeper a segment names."""
    sources = {s["sourceId"] for s in plan["segments"] if s.get("sourceId")}
    sources |= {b["sourceId"] for b in plan["audio"]["bed"] if b.get("sourceId")}
    return {"planId": plan["planId"], "planRevision": plan["planRevision"], "projectId": plan["projectId"],
            "editPlanSha256": canonical_sha256(plan),
            "bindings": {key: plan["bindings"][key] for key in BINDINGS},
            "sourceIds": sorted(sources),
            "keeperIds": sorted({s["keeperId"] for s in plan["segments"] if s.get("keeperId")})}


def film_dependencies(film: dict) -> dict:
    """What a delivered film (jovra.delivered-artifact/1) depends on: the plan it was rendered from."""
    return {"artifactId": film["artifactId"], "projectId": film["projectId"],
            "editPlanSha256": film["bindings"]["editPlanSha256"], "stale": film["stale"] is not None}


def _revision(value, what: str) -> int:
    require(type(value) is int and value >= 1, "badRevision", f"{what} must be a revision (an integer from 1)")
    return value


def _ordered(reasons: set) -> list:
    return [r for r in REASON_ORDER if r in reasons]


def propagate(state: dict, changes: list) -> dict:
    """state = {projects: {projectId: {eventRevision, syncRevision, keeperCatalogRevision}}, plans: [plan
    dependencies], films: [film dependencies]}; changes = [{kind, projectId, revision, sourceIds | keeperIds}]."""
    projects = copy.deepcopy(state["projects"])
    for pid, current in projects.items():
        require(sorted(current) == sorted(BINDINGS), "badState", f"project {pid} revisions {sorted(current)}")
        for key in BINDINGS:
            _revision(current[key], f"{pid} {key}")
    plans = []
    seen = set()
    for dep in state["plans"]:
        require(dep["projectId"] in projects, "unknownProject", f"plan {dep['planId']}: project {dep['projectId']}")
        require(dep["planId"] not in seen, "duplicateId", f"plan {dep['planId']} listed twice")
        seen.add(dep["planId"])
        current = projects[dep["projectId"]]
        reasons = set()
        for kind, (key, reason) in KINDS.items():
            bound = _revision(dep["bindings"][key], f"{dep['planId']} {key}")
            require(bound <= current[key], "futureRevision", f"{dep['planId']} is bound to {key} {bound}, "
                                                             f"ahead of the project ({current[key]})")
            if bound < current[key]:
                reasons.add(reason)   # already behind before any change: stale
        plans.append({"dep": dep, "bindings": dict(dep["bindings"]), "reasons": reasons})

    for change in changes:
        kind = change["kind"]
        require(kind in KINDS, "unknownChange", f"change kind {kind!r}")
        pid = change["projectId"]
        require(pid in projects, "unknownProject", f"change for project {pid}")
        key, reason = KINDS[kind]
        revision = _revision(change["revision"], f"{kind} revision")
        require(revision > projects[pid][key], "revisionNotIncreasing",
                f"{key} {revision} is not after the current {projects[pid][key]}")
        named = set(change.get("sourceIds" if kind == "sync" else "keeperIds", []))
        require(kind == "event" or named, "badChange", f"a {kind} change names what changed")
        for plan in plans:
            dep = plan["dep"]
            if dep["projectId"] != pid:
                continue
            uses = dep["sourceIds"] if kind == "sync" else dep["keeperIds"]
            if kind == "event" or named & set(uses):
                plan["reasons"].add(reason)
            elif plan["bindings"][key] == projects[pid][key]:
                plan["bindings"][key] = revision   # nothing it uses changed: carried to the new revision
        projects[pid][key] = revision

    by_hash = {p["dep"]["editPlanSha256"]: p for p in plans}
    films = []
    for film in state["films"]:
        plan = by_hash.get(film["editPlanSha256"])
        require(plan is not None, "unknownPlan", f"film {film['artifactId']}: no listed plan has its edit-plan hash")
        require(plan["dep"]["projectId"] == film["projectId"], "unknownPlan", f"film {film['artifactId']}: plan of "
                                                                             "another project")
        stale = film["stale"] or bool(plan["reasons"])
        films.append({"artifactId": film["artifactId"], "projectId": film["projectId"],
                      "planId": plan["dep"]["planId"], "status": "stale" if stale else "current",
                      "label": FILM_LABEL if stale else None, "reasons": _ordered(plan["reasons"]),
                      "keptAsVersion": True})
    out_plans = [{"planId": p["dep"]["planId"], "projectId": p["dep"]["projectId"],
                  "status": "stale" if p["reasons"] else "current", "reasons": _ordered(p["reasons"]),
                  "bindings": p["bindings"]} for p in plans]
    return {"current": projects, "plans": out_plans, "films": films,
            "stalePlanIds": sorted(p["planId"] for p in out_plans if p["status"] == "stale"),
            "staleFilmIds": sorted(f["artifactId"] for f in films if f["status"] == "stale")}


def run_vector(case: dict) -> dict:
    """A staleness vector case -> the result, or {"rejectCode": code} when the reference refuses it."""
    try:
        return propagate(case["input"]["state"], case["input"]["changes"])
    except Reject as exc:
        return {"rejectCode": exc.code}
