"""Explicit reviewed order observations (ADR0030), shared by the scoring reference and its ports."""
from .log import LogError

KINDS = ("serverOverride", "receiverOverride")


class OrderOverrides:
    def __init__(self, setup, log, placed):
        self.mode = setup.get("resolutionMode", "rules")
        if self.mode not in ("rules", "asPlayed"):
            raise LogError("invalidResolutionMode", self.mode)
        side_of = {pid: side for side, players in setup["sides"].items() for pid in players}
        doubles = len(setup["sides"]["A"]) == 2
        by_id = {event["id"]: event for event in log}
        for event in log:
            if event["type"] not in KINDS: continue
            target = by_id.get(event["targetPointId"])
            if target is None: raise LogError("overrideTargetMissing", event["id"])
            if target["type"] != "point" or target["seq"] >= event["seq"]:
                raise LogError("overrideTargetInvalid", event["id"])
            names = [event["server"]] if event["type"] == "serverOverride" else [event["deuceReceiver"]]
            names += event.get("rotation", [])
            if any(pid not in side_of for pid in names): raise LogError("unknownPlayer", event["id"])
            if event.get("provenance") not in ("manual", "reviewed"):
                raise LogError("overrideMetadataInvalid", event["id"])
            if event["type"] == "receiverOverride":
                if not doubles or event["receivingSide"] not in ("A", "B") or side_of[event["deuceReceiver"]] != event["receivingSide"]:
                    raise LogError("receiverOverrideInvalid", event["id"])
                continue
            continuation = event["continuation"]
            if continuation not in ("pointOnly", "completedStandardGame", "oddTiebreak"):
                raise LogError("overrideMetadataInvalid", event["id"])
            if continuation == "pointOnly":
                if "discoveryAfterPointId" in event or "rotation" in event:
                    raise LogError("overrideMetadataInvalid", event["id"])
            elif event.get("discoveryAfterPointId") != event["targetPointId"]:
                raise LogError("overrideMetadataInvalid", event["id"])
            elif doubles:
                rotation = event.get("rotation", [])
                if len(rotation) != 4 or set(rotation) != set(side_of) or rotation[0] != event["server"] or any(
                    side_of[rotation[i]] == side_of[rotation[(i+1) % 4]] for i in range(4)):
                    raise LogError("overrideRotationInvalid", event["id"])
            elif "rotation" in event:
                raise LogError("overrideRotationInvalid", event["id"])
        active_points = {event["id"] for event in placed if event["type"] == "point"}
        self.servers, self.receivers = {}, {}
        for event in placed:
            if event["type"] not in KINDS or event["targetPointId"] not in active_points: continue
            collection = self.servers if event["type"] == "serverOverride" else self.receivers
            collection[event["targetPointId"]] = event
        self.receiving_orders = {}

    def before_point(self, match, event, winner, conflicts):
        server = match.server()
        observation = self.servers.get(event["id"])
        if observation:
            observed = observation["server"]
            if self.mode == "rules":
                if observed != server:
                    conflicts.append({"type": "serverMismatch", "pointId": event["id"], "recorded": observed, "derived": server})
            else:
                server = observed
                continuation = observation["continuation"]
                valid = continuation == "pointOnly"
                if continuation == "completedStandardGame":
                    valid = match.tb is None and winner is not None and match.clone().apply_point(winner)["gameWon"]
                elif continuation == "oddTiebreak":
                    valid = match.tb is not None and (match.point_in_game + 1) % 2 == 1
                if not valid:
                    conflicts.append({"type": "overrideContextChanged", "eventId": observation["id"], "pointId": event["id"]})
                elif continuation != "pointOnly":
                    offset = (match.point_in_game + 1) // 2 if match.tb else 0
                    side = match.side_of[server]
                    match.first_side = side if (match.match_game + offset) % 2 == 0 else ("B" if side == "A" else "A")
                    if match.doubles:
                        rotation = observation["rotation"]
                        current = (match.game_in_set + offset) % 4
                        match.rotation = [rotation[(i-current) % 4] for i in range(4)]
        receiver = self.receivers.get(event["id"])
        if receiver and self.mode == "rules":
            derived = match.deuce_receivers[receiver["receivingSide"]]
            if receiver["deuceReceiver"] != derived:
                conflicts.append({"type": "receiverMismatch", "pointId": event["id"],
                                  "recorded": receiver["deuceReceiver"], "derived": derived})
        if receiver and self.mode == "asPlayed":
            side = "B" if match.side_of[server] == "A" else "A"
            if receiver["receivingSide"] != side:
                conflicts.append({"type": "overrideContextChanged", "eventId": receiver["id"], "pointId": event["id"]})
            else:
                self.receiving_orders[side] = (match.match_game, receiver["deuceReceiver"])
        return server

    def receiver(self, match, server, court_side):
        default = match.receiver(server, court_side)
        side = "B" if match.side_of[server] == "A" else "A"
        override = self.receiving_orders.get(side)
        if override and override[0] == match.match_game and court_side is not None:
            return override[1] if court_side == "deuce" else match.partner(override[1])
        return default
