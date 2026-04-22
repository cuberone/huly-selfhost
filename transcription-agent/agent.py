"""
LiveKit transcription agent for Huly meetings.

Auto-joins every LiveKit room (dispatched by the LiveKit server when a room
is created), subscribes to every participant's microphone track, runs each
track through Deepgram, and publishes TranscriptionSegments back to the room
so the Huly front-end renders them in the meeting UI.
"""

import asyncio
import logging

from livekit import agents, rtc
from livekit.agents import AutoSubscribe, JobContext, WorkerOptions, cli, stt
from livekit.plugins import deepgram

logger = logging.getLogger("huly-transcriber")
logging.basicConfig(level=logging.INFO)


async def _forward_segments(
    stream: stt.SpeechStream,
    forwarder: agents.transcription.STTSegmentsForwarder,
) -> None:
    async for ev in stream:
        if ev.type in (stt.SpeechEventType.INTERIM_TRANSCRIPT, stt.SpeechEventType.FINAL_TRANSCRIPT):
            forwarder.update(ev)


async def _transcribe_track(
    ctx: JobContext,
    participant: rtc.RemoteParticipant,
    track: rtc.Track,
) -> None:
    logger.info("transcribing track from %s", participant.identity)
    audio_stream = rtc.AudioStream(track)
    stt_impl = deepgram.STT(model="nova-2", language="multi")
    stt_stream = stt_impl.stream()
    forwarder = agents.transcription.STTSegmentsForwarder(
        room=ctx.room, participant=participant, track=track,
    )
    asyncio.create_task(_forward_segments(stt_stream, forwarder))
    async for ev in audio_stream:
        stt_stream.push_frame(ev.frame)


async def entrypoint(ctx: JobContext) -> None:
    logger.info("joining room: %s", ctx.room.name)
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)

    @ctx.room.on("track_subscribed")
    def _on_track_subscribed(
        track: rtc.Track,
        publication: rtc.TrackPublication,
        participant: rtc.RemoteParticipant,
    ) -> None:
        if track.kind == rtc.TrackKind.KIND_AUDIO:
            asyncio.create_task(_transcribe_track(ctx, participant, track))


if __name__ == "__main__":
    cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint))
