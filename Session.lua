local HL = HelloLog
local Session = {}
HL.Session = Session

Session.recording = false
Session.current = nil
Session.lastResumeAt = nil

local function ensureBucket(zone)
    local sessions = HL.db.sessions
    if not sessions[zone] then
        sessions[zone] = {
            zone = zone,
            items = {},
            money = 0,
            createdAt = time(),
            secondsActive = 0,
            perMob = {},
            factions = {},
        }
    end
    return sessions[zone]
end

local function flushTime()
    if Session.lastResumeAt and Session.current then
        Session.current.secondsActive = (Session.current.secondsActive or 0)
            + (time() - Session.lastResumeAt)
    end
    Session.lastResumeAt = nil
end

local function rotateToCurrentZone()
    local zone = GetRealZoneText()
    if not zone or zone == "" then zone = "Unknown" end
    if Session.current and Session.current.zone == zone then
        if Session.recording and not Session.lastResumeAt then
            Session.lastResumeAt = time()
        end
        return
    end
    flushTime()
    if Session.recording then
        Session.current = ensureBucket(zone)
        Session.lastResumeAt = time()
    else
        -- Idle: if a paused recording exists (state.zone set after Pause),
        -- keep its bucket attached so the panel keeps showing the paused
        -- timer/money even as the player wanders into other zones. After a
        -- full Stop state.zone is nil, so the panel correctly goes blank.
        local pausedZone = HL.db.state and HL.db.state.zone
        Session.current = pausedZone and HL.db.sessions[pausedZone] or nil
    end
end

local function logZoneChange(zone)
    if not Session.current then return end
    zone = zone or GetRealZoneText()
    if not zone or zone == "" then zone = "Unknown" end
    local list = Session.current.zoneChanges
    if not list then
        list = {}
        Session.current.zoneChanges = list
    end
    local last = list[#list]
    if last and last.zone == zone then return end
    list[#list + 1] = { time = time(), zone = zone }
end

local function resumeLockedZone()
    -- Re-attach Session.current to the locked recording bucket (if any).
    -- Used on PLAYER_ENTERING_WORLD when we were recording, so /reload
    -- and post-reload zone-loads don't switch us off the recording zone.
    local zone = HL.db.state and HL.db.state.zone
    if not zone then return false end
    local sess = HL.db.sessions and HL.db.sessions[zone]
    if not sess then return false end
    Session.current = sess
    if Session.recording then
        Session.lastResumeAt = time()
    end
    return true
end

function Session:Init()
    HL.db.state = HL.db.state or {}
    self.recording = HL.db.state.recording == true

    HL:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
        -- While recording, the bucket is locked to the zone we started in,
        -- but we still log the visit so the timeline shows where the
        -- player went. When idle, follow the player so the panel reflects
        -- the zone they are standing in.
        if self.recording then
            logZoneChange()
        else
            rotateToCurrentZone()
        end
        HL.UI:Refresh()
    end)
    HL:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if self.recording and resumeLockedZone() then
            -- restored
        else
            rotateToCurrentZone()
        end
        HL.UI:Refresh()
    end)
end

function Session:Start()
    self.recording = true
    HL.db.state.recording = true
    if HL.db.state.zone and HL.db.sessions[HL.db.state.zone] then
        -- Resume the previously locked bucket, even if the player has
        -- since walked into another zone.
        self.current = HL.db.sessions[HL.db.state.zone]
        if not self.lastResumeAt then self.lastResumeAt = time() end
    else
        rotateToCurrentZone()
        HL.db.state.zone = self.current and self.current.zone or nil
        logZoneChange(self.current and self.current.zone)
    end
    HL:Print("recording " .. (self.current and self.current.zone or "?"))
    HL.UI:Refresh()
end

function Session:Stop()
    flushTime()
    self.recording = false
    HL.db.state.recording = false
    HL:Print("stopped")
    HL.UI:Refresh()
end

function Session:Tick()
    if not self.recording or not self.current or not self.lastResumeAt then return end
    local now = time()
    self.current.secondsActive = (self.current.secondsActive or 0) + (now - self.lastResumeAt)
    self.lastResumeAt = now
end

local function archiveCurrent()
    flushTime()
    local sess = Session.current
    if sess then
        HL.db.history = HL.db.history or {}
        sess.closedAt = time()
        table.insert(HL.db.history, sess)
        HL.db.sessions[sess.zone] = nil
    end
    Session.current = nil
    return sess
end

local function isEmpty(sess)
    if not sess then return true end
    if (sess.money or 0) ~= 0 then return false end
    for _, b in pairs(sess.items or {}) do
        if (b.count or 0) > 0 then return false end
    end
    for _, p in pairs(sess.perMob or {}) do
        if (p.kills or 0) > 0 then return false end
    end
    for _, f in pairs(sess.factions or {}) do
        if (f.delta or 0) ~= 0 then return false end
    end
    if sess.deaths and #sess.deaths > 0 then return false end
    return true
end

function Session:Close()
    flushTime()
    local sess = Session.current
    self.recording = false
    HL.db.state.recording = false
    HL.db.state.zone = nil
    if not sess then
        HL:Print("no open session")
        HL.UI:Refresh()
        return
    end
    local zone = sess.zone
    if isEmpty(sess) then
        HL.db.sessions[zone] = nil
        Session.current = nil
        HL:Print("discarded empty " .. zone .. " session")
    else
        archiveCurrent()
        HL.Detail:ShowHistoryEntry(#HL.db.history)
        HL:Print("ended " .. zone)
    end
    HL.UI:Refresh()
end

function Session:New()
    archiveCurrent()
    self.recording = true
    HL.db.state.recording = true
    rotateToCurrentZone()
    HL.db.state.zone = self.current and self.current.zone or nil
    logZoneChange(self.current and self.current.zone)
    HL:Print("new session " .. (self.current and self.current.zone or "?"))
    HL.UI:Refresh()
end

function Session:Reset()
    flushTime()
    HL.db.sessions = {}
    self.current = nil
    self.lastResumeAt = nil
    if self.recording then
        rotateToCurrentZone()
        HL.db.state.zone = self.current and self.current.zone or nil
    else
        HL.db.state.zone = nil
    end
    HL:Print("reset")
    HL.UI:Refresh()
end

function Session:DeleteHistory(index)
    HL.db.history = HL.db.history or {}
    local entry = HL.db.history[index]
    if not entry then return end
    table.remove(HL.db.history, index)
    HL:Print("deleted " .. (entry.zone or "?") .. " session")
    HL.UI:Refresh()
end

function Session:Wipe()
    self.recording = false
    self.current = nil
    self.lastResumeAt = nil
    HL.db.sessions = {}
    HL.db.history = {}
    HL.db.state = { recording = false }
    HL:Print("wiped all session and history data.")
    HL.UI:Refresh()
end

function Session:IsRecording()
    return self.recording
end

function Session:Current()
    return self.current
end

function Session:ElapsedSeconds()
    local sess = self.current
    if not sess then return 0 end
    local total = sess.secondsActive or 0
    if self.recording and self.lastResumeAt then
        total = total + (time() - self.lastResumeAt)
    end
    return total
end

function Session:ItemCount()
    local sess = self.current
    if not sess then return 0 end
    local n = 0
    for _, b in pairs(sess.items) do n = n + (b.count or 0) end
    return n
end
