# Bounded native capture service slice

Part of T17/#19 and the authorized single record → library → replay → corrected score → export flow. This slice provides one application-local session service and a RecordingSink that calls the accepted atomic SessionStore.saveCapture API. It does not close T17, T20 or T28.

Pre-agreed seams: capture preserves the caller’s explicit match format and toss; a fresh capture becomes retrievable through the service without any inherited sample points, annotations or exports; fixture origin is explicit Sample; a sink handoff persists recording and marks together and remains retrievable after reopening. These derive from the recording/storage acceptance contracts and root’s explicit native service/sink assignment. Tests use public service interfaces and real isolated temporary folders, not internal call counts.

Fresh branch codex/t17-core-capture-service reuses the owned managed checkout; current main custody49856d2 is integrated, T12 publication76f14f9 subsequently merged35117e1. Sole native simulator4265ADFD-39A3-4E71-8482-1945DDB5F899 was the sole simulator used during root-reserved serial compile turns.

Full T17 UI, confirmation/control sizing, slots, recovery, interruption/landscape/AX5, delete confirmation and physical camera tests remain pending. Studio/Android/watch/tablet work and step5 remain held.
