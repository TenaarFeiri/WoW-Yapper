# WoW Chat Systems Test Matrix (Source Audit)

This matrix is based on local Blizzard UI source in wow-ui-source and is intended to drive exhaustive Yapper validation.

## Blizzard Source Anchors

- Core chat routing/open/activate/deactivate and whisper reply memory:
  - wow-ui-source/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua
- Edit box parsing and send dispatch behavior:
  - wow-ui-source/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua
- Chat type definitions and event groupings:
  - wow-ui-source/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatTypeInfoConstants.lua
- Temporary whisper windows and whisper popout behavior:
  - wow-ui-source/Interface/AddOns/Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua
  - wow-ui-source/Interface/AddOns/Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua
- Voice transcription chat mode mapping:
  - wow-ui-source/Interface/AddOns/Blizzard_ChatFrame/Shared/VoiceChatTranscriptionFrame.lua

## Practical Outbound Chat Systems

1. Public text modes
- SAY
- EMOTE
- YELL

2. Group text modes
- PARTY
- PARTY_LEADER
- RAID
- RAID_LEADER
- RAID_WARNING
- INSTANCE_CHAT
- INSTANCE_CHAT_LEADER

3. Guild text modes
- GUILD
- OFFICER

4. Direct message modes
- WHISPER
- BN_WHISPER

5. Channel modes
- CHANNEL (numbered channels + communities channels added into chat channel list)
- CLUB/communities stream path (C_Club.SendMessage)

6. Voice text mode
- VOICE_TEXT (voice transcription/speak-for-me path)

## Key Blizzard Mechanics That Must Be Covered

1. Open and focus control
- OpenChat chooses edit box based on chat style and active frame state.
- ActivateChat/DeactivateChat transitions can occur independently of send.

2. Whisper memory and reply flow
- Last tell and last told target are tracked separately.
- ReplyTell and ReplyTell2 restore type/target from that memory.

3. Temporary whisper frames
- Temporary whisper windows set frame chatType/chatTarget and editBox tell target.
- whisperMode variants (inline/popout/popout_and_inline) alter routing and suppression.

4. Parsing and dispatch
- Slash parsing can mutate type and target before send.
- WHISPER dispatch uses SendChatMessage(type,target).
- BN_WHISPER dispatch uses C_BattleNet.SendWhisper(accountID).
- CHANNEL dispatch sends with channel target.

5. Communities path
- Communities streams can be represented as channel names and resolved to channel IDs.
- Club stream send path exists outside plain numbered channels.

6. Voice text path
- Voice transcription frame maps voice channel context to PARTY/RAID/INSTANCE/GUILD/OFFICER/COMMUNITIES_CHANNEL.
- VOICE_TEXT sticky handling can reassert after sending in voice tab contexts.

## Yapper Coverage Mapping (Current)

1. Covered by router/send path
- Standard SendChatMessage text modes (public, group, guild, whisper, channel).
- BN whisper path (C_BattleNet.SendWhisper with fallback resolution).
- Club/community stream path via CLUB and CHANNEL community detection.

2. Covered by channel policy harness
- Whisper target preservation under transient nil-target conditions.
- Incoming whisper affinity guard.
- Non-target mode stale-target clearing.
- Invalid CHANNEL target fallback.

3. Not fully modeled in harness (requires in-game/integration scenarios)
- whisperMode popout and popout_and_inline transitions.
- Classic vs IM chatStyle focus behavior.
- Voice transcription tab/VOICE_TEXT behavior.
- GM whisper frame special handling.

## Exhaustive Test Plan

1. Automated (local Lua harness)
- Keep policy harness as deterministic invariants:
  - tools/2.0testsuites/test_channel_policy_chat_modes.lua

2. In-game integration sweep
- Public: SAY/EMOTE/YELL.
- Group: PARTY/PARTY_LEADER/RAID/RAID_LEADER/RAID_WARNING/INSTANCE_CHAT/INSTANCE_CHAT_LEADER with group state transitions.
- Guild: GUILD/OFFICER in and out of guild.
- Whisper: WHISPER, BN_WHISPER, ReplyTell, ReplyTell2.
- Whisper tab behavior in docked and undocked windows under each whisperMode setting.
- Channels: numbered channels and communities channel streams (add/remove channel and send).
- Voice: VOICE_TEXT active/inactive with speak-for-me enabled/disabled.
- Lockdown transitions: send and reopen before/during/after lockdown.

3. Regression priority
- DM tab stays bound to target after incoming reply and subsequent enter.
- No fallback to SAY unless target truly unavailable and no valid frame/affinity/existing selection context exists.
