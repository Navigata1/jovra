import Foundation

// The Sample records the demo client replays, byte for byte from spec/studio/fixtures/records, so the app never reads
// spec/ at runtime. CloudDemoFixtureSourceTests fails when any text differs from the repository's copy.
public enum DemoCloudFixtureSource {
    /// `records/render-job.queue-sample.json` (its trailing newline is restored by `texts`)
    static let queueSampleJob = #"""
{
  "schemaVersion": "jovra.render-job/1",
  "jobId": "job-queue-38",
  "projectId": "sample-court-day",
  "environment": "test",
  "sample": true,
  "planId": "court-memories-storyboard",
  "planRevision": 1,
  "quoteId": "quote-test-00",
  "reservationId": "res-0001",
  "idempotencyKey": "4dca1b2af2d5acb331ffd8654c9c26c818dab903ec08d38277f5683ed7570019",
  "state": "preview_rendering",
  "resumeStage": null,
  "attempt": 1,
  "maxAttempts": 3,
  "stageProgress": {
    "stage": "preview_rendering",
    "percent": 42,
    "sample": true
  },
  "deliveredArtifactIds": [],
  "history": [
    {
      "seq": 0,
      "from": null,
      "to": "draft",
      "at": "2026-10-07T22:44:00Z",
      "reason": "created"
    },
    {
      "seq": 1,
      "from": "draft",
      "to": "quoted",
      "at": "2026-10-07T22:45:00Z",
      "reason": "preflight"
    },
    {
      "seq": 2,
      "from": "quoted",
      "to": "consented",
      "at": "2026-10-07T22:50:00Z",
      "reason": "owner-accepted"
    },
    {
      "seq": 3,
      "from": "consented",
      "to": "upload_pending",
      "at": "2026-10-07T22:50:05Z",
      "reason": "reserved"
    },
    {
      "seq": 4,
      "from": "upload_pending",
      "to": "uploading",
      "at": "2026-10-07T22:51:00Z",
      "reason": "upload-started"
    },
    {
      "seq": 5,
      "from": "uploading",
      "to": "queued",
      "at": "2026-10-07T23:03:00Z",
      "reason": "sources-verified"
    },
    {
      "seq": 6,
      "from": "queued",
      "to": "normalizing",
      "at": "2026-10-07T23:04:00Z",
      "reason": "stage-start"
    },
    {
      "seq": 7,
      "from": "normalizing",
      "to": "syncing",
      "at": "2026-10-07T23:08:00Z",
      "reason": "stage-start"
    },
    {
      "seq": 8,
      "from": "syncing",
      "to": "planning",
      "at": "2026-10-07T23:12:00Z",
      "reason": "analysis-unavailable-manual-fallback"
    },
    {
      "seq": 9,
      "from": "planning",
      "to": "preview_rendering",
      "at": "2026-10-07T23:13:00Z",
      "reason": "plan-valid"
    }
  ]
}
"""#

    /// `records/render-job.ready.json` (its trailing newline is restored by `texts`)
    static let readyJob = #"""
{
  "schemaVersion": "jovra.render-job/1",
  "jobId": "job-film-01",
  "projectId": "sample-court-day",
  "environment": "test",
  "sample": true,
  "planId": "court-memories-final",
  "planRevision": 2,
  "quoteId": "quote-test-01",
  "reservationId": "res-0002",
  "idempotencyKey": "8e10e6614d128e6380090e9b206cac5e6ee800e17cce73cc23e823114efffb99",
  "state": "ready",
  "resumeStage": null,
  "attempt": 2,
  "maxAttempts": 3,
  "stageProgress": null,
  "deliveredArtifactIds": [
    "film-court-memories"
  ],
  "history": [
    {
      "seq": 0,
      "from": null,
      "to": "draft",
      "at": "2026-10-07T22:44:00Z",
      "reason": "created"
    },
    {
      "seq": 1,
      "from": "draft",
      "to": "quoted",
      "at": "2026-10-07T22:45:00Z",
      "reason": "preflight"
    },
    {
      "seq": 2,
      "from": "quoted",
      "to": "consented",
      "at": "2026-10-07T22:50:00Z",
      "reason": "owner-accepted"
    },
    {
      "seq": 3,
      "from": "consented",
      "to": "upload_pending",
      "at": "2026-10-07T22:50:05Z",
      "reason": "reserved"
    },
    {
      "seq": 4,
      "from": "upload_pending",
      "to": "uploading",
      "at": "2026-10-07T22:51:00Z",
      "reason": "upload-started"
    },
    {
      "seq": 5,
      "from": "uploading",
      "to": "paused",
      "at": "2026-10-07T22:55:00Z",
      "reason": "owner-paused"
    },
    {
      "seq": 6,
      "from": "paused",
      "to": "uploading",
      "at": "2026-10-07T22:58:00Z",
      "reason": "owner-resumed"
    },
    {
      "seq": 7,
      "from": "uploading",
      "to": "queued",
      "at": "2026-10-07T23:03:00Z",
      "reason": "sources-verified"
    },
    {
      "seq": 8,
      "from": "queued",
      "to": "normalizing",
      "at": "2026-10-07T23:04:00Z",
      "reason": "stage-start"
    },
    {
      "seq": 9,
      "from": "normalizing",
      "to": "syncing",
      "at": "2026-10-07T23:08:00Z",
      "reason": "stage-start"
    },
    {
      "seq": 10,
      "from": "syncing",
      "to": "analyzing",
      "at": "2026-10-07T23:10:00Z",
      "reason": "stage-start"
    },
    {
      "seq": 11,
      "from": "analyzing",
      "to": "planning",
      "at": "2026-10-07T23:14:00Z",
      "reason": "stage-start"
    },
    {
      "seq": 12,
      "from": "planning",
      "to": "preview_rendering",
      "at": "2026-10-07T23:15:00Z",
      "reason": "plan-valid"
    },
    {
      "seq": 13,
      "from": "preview_rendering",
      "to": "awaiting_review",
      "at": "2026-10-07T23:22:00Z",
      "reason": "preview-ready"
    },
    {
      "seq": 14,
      "from": "awaiting_review",
      "to": "final_rendering",
      "at": "2026-10-07T23:30:00Z",
      "reason": "owner-approved"
    },
    {
      "seq": 15,
      "from": "final_rendering",
      "to": "failed_retryable",
      "at": "2026-10-07T23:33:00Z",
      "reason": "lease-lost"
    },
    {
      "seq": 16,
      "from": "failed_retryable",
      "to": "final_rendering",
      "at": "2026-10-07T23:34:00Z",
      "reason": "retry"
    },
    {
      "seq": 17,
      "from": "final_rendering",
      "to": "verifying",
      "at": "2026-10-07T23:44:00Z",
      "reason": "render-done"
    },
    {
      "seq": 18,
      "from": "verifying",
      "to": "ready",
      "at": "2026-10-07T23:49:00Z",
      "reason": "verification-passed"
    }
  ]
}
"""#

    /// `records/quote.sample-illustrative.json` (its trailing newline is restored by `texts`)
    static let sampleQuote = #"""
{
  "schemaVersion": "jovra.quote/1",
  "quoteId": "quote-sample-37",
  "projectId": "sample-court-day",
  "environment": "demo",
  "sample": true,
  "illustrative": true,
  "planRevision": 1,
  "outputSpecSha256": "4dca1b2af2d5acb331ffd8654c9c26c818dab903ec08d38277f5683ed7570019",
  "inputsSha256": "d965733c590ea810c2b04a6866889113498b6e1341a797b11ea9b5e63af3084b",
  "plannerChoice": "model",
  "filmClass": "story-2-3",
  "estimate": {
    "minCredits": 2,
    "maxCredits": 4
  },
  "capCredits": 4,
  "estimatedMaxCostMicroUsd": 1290000,
  "creditCostBudgetMicroUsd": 800000,
  "lineItems": {
    "sourceCount": 3,
    "uploadBytes": 10800000000,
    "storageDays": 7,
    "outputSeconds": 300,
    "renderMinutesEstimate": 30,
    "plannerTokensEstimate": 120000
  },
  "retentionDays": 7,
  "displayAmounts": {
    "currency": "USD",
    "minMinor": 400,
    "maxMinor": 800,
    "capMinor": 1200,
    "illustrative": true
  },
  "createdAt": "2026-10-07T22:45:00Z",
  "expiresAt": "2026-10-07T23:15:00Z",
  "status": "open",
  "acceptedAt": null,
  "consent": null
}
"""#

    /// `records/delivered-artifact.film.json` (its trailing newline is restored by `texts`)
    static let filmArtifact = #"""
{
  "schemaVersion": "jovra.delivered-artifact/1",
  "artifactId": "film-court-memories",
  "projectId": "sample-court-day",
  "jobId": "job-film-01",
  "environment": "test",
  "sample": true,
  "kind": "film",
  "variant": "primary",
  "titleText": "A good day on court",
  "renderer": {
    "kind": "ffmpeg",
    "version": "jovra-render-ffmpeg@0.1.0"
  },
  "media": {
    "container": "mp4",
    "videoCodec": "h264",
    "audioCodec": "aac",
    "width": 1920,
    "height": 1080,
    "fps": {
      "num": 30,
      "den": 1
    },
    "durationFrames": 7740,
    "audioSampleCount": 12384000,
    "sizeBytes": 412000000,
    "sha256": "9891915899c5ddbc48f6a4d659ea5245ef57ee857164eda6db8ebc36bb98e6bf"
  },
  "chapters": [
    {
      "id": "ch-arrival",
      "templateId": "chapter.arrival",
      "startFrame": 0,
      "endFrame": 1260
    },
    {
      "id": "ch-match",
      "templateId": "chapter.match",
      "startFrame": 1260,
      "endFrame": 5490
    },
    {
      "id": "ch-after",
      "templateId": "chapter.after",
      "startFrame": 5490,
      "endFrame": 7740
    }
  ],
  "captions": null,
  "bindings": {
    "sourceSha256s": [
      "3dd8384c35d332710ba3248a9588d8e274ddff6d26ceb2b2dfe409ca2b2051ff",
      "637ced057c91240f310c4e851bafb3213cf886594d669f861e415d70dd1b8318",
      "edbc43ac3cabeaaad090552b0b684ad0c4d0e84ba7646855bf68467d387793ab",
      "02c2897f6e82f64e6f5f5d5b6588e844ebacc1c16990f7ada82f86e8a51a1321"
    ],
    "sourceManifestRevision": 1,
    "syncRevision": 2,
    "eventRevision": 3,
    "profile": {
      "id": "court-memories",
      "revision": 1
    },
    "planner": {
      "kind": "heuristic",
      "modelId": null
    },
    "editPlanSha256": "4d768ced3b6181944a086e7a79cfab5d7e95f86730d5262a58fca57b290a50b3",
    "storyBriefRevision": 1
  },
  "verification": {
    "status": "passed",
    "probe": "passed",
    "fullDecode": "passed",
    "frameCount": "passed",
    "audio": "passed",
    "overlayProvenance": "passed",
    "checkedAt": "2026-10-07T23:48:30Z"
  },
  "delivery": {
    "visibility": "private",
    "shareLink": {
      "grantId": "grant-01",
      "issuedAt": "2026-10-07T23:50:00Z",
      "expiresAt": "2026-10-08T23:50:00Z"
    },
    "retention": {
      "policy": "keep-until-deleted",
      "days": null
    }
  },
  "youtubePrep": {
    "prepared": true,
    "published": false
  },
  "stale": null
}
"""#

    /// The embedded texts by fixture file name, exactly as on disk.
    public static var texts: [String: String] {
        ["render-job.queue-sample.json": queueSampleJob + "\n", "render-job.ready.json": readyJob + "\n", "quote.sample-illustrative.json": sampleQuote + "\n", "delivered-artifact.film.json": filmArtifact + "\n"]
    }
}
