#include "helpercore.h"

HelperCore g_helperCore;

void HelperCore::clearCooldowns()
{
    m_spellsCooldown.clear();
    m_groupsCooldown.clear();
    m_multiUseCooldownEnd = 0;
}

void HelperCore::setSpellCooldown(int spellId, int delay)
{
    m_spellsCooldown[spellId] = g_clock.millis() + delay;
}

void HelperCore::setSpellCooldownEndTime(int spellId, ticks_t endTime)
{
    m_spellsCooldown[spellId] = endTime;
}

int HelperCore::getSpellCooldown(int spellId)
{
    auto it = m_spellsCooldown.find(spellId);
    if (it != m_spellsCooldown.end())
        return static_cast<int>(it->second);
    return 0;
}

bool HelperCore::isSpellOnCooldown(int spellId)
{
    auto it = m_spellsCooldown.find(spellId);
    if (it != m_spellsCooldown.end())
        return it->second > g_clock.millis();
    return false;
}

void HelperCore::setGroupCooldown(int groupId, int delay)
{
    m_groupsCooldown[groupId] = g_clock.millis() + delay;
}

int HelperCore::getGroupCooldown(int groupId)
{
    auto it = m_groupsCooldown.find(groupId);
    if (it != m_groupsCooldown.end())
        return static_cast<int>(it->second);
    return 0;
}

bool HelperCore::isGroupOnCooldown(int groupId)
{
    auto it = m_groupsCooldown.find(groupId);
    if (it != m_groupsCooldown.end())
        return it->second > g_clock.millis();
    return false;
}

void HelperCore::setMultiUseCooldown(int delay)
{
    ticks_t now = g_clock.millis();
    ticks_t newExpiry = now + delay;
    if (m_multiUseCooldownEnd <= now || newExpiry > m_multiUseCooldownEnd + 50)
        m_multiUseCooldownEnd = newExpiry;
}

bool HelperCore::isMultiUseOnCooldown()
{
    return m_multiUseCooldownEnd > g_clock.millis();
}

int HelperCore::translateVocation(int vocation)
{
    switch (vocation) {
        case 1: case 11: return 1;
        case 2: case 12: return 2;
        case 3: case 13: return 3;
        case 4: case 14: return 4;
        case 5: case 15: return 5;
        default: return vocation;
    }
}

std::vector<int> HelperCore::getClientVocationsForServerVoc(int serverVocId)
{
    switch (serverVocId) {
        case 1: case 11: return { 1, 11 };
        case 2: case 12: return { 2, 12 };
        case 3: case 13: return { 3, 13 };
        case 4: case 14: return { 4, 14 };
        case 5: case 15: return { 5, 15 };
        default: return {};
    }
}

bool HelperCore::canUseByServerVoc(const std::vector<int>& spellVocations, int serverVocId)
{
    auto mapped = getClientVocationsForServerVoc(serverVocId);
    if (mapped.empty())
        return false;
    for (int clientVoc : mapped) {
        for (int spellVoc : spellVocations) {
            if (clientVoc == spellVoc)
                return true;
        }
    }
    return false;
}

int HelperCore::getDistanceBetween(const Position& p1, const Position& p2)
{
    return std::max(std::abs(p1.x - p2.x), std::abs(p1.y - p2.y));
}

bool HelperCore::positionCompare(const Position& p1, const Position& p2)
{
    return p1.x == p2.x && p1.y == p2.y && p1.z == p2.z;
}

int HelperCore::getDirectionTo(const Position& fromPos, const Position& toPos)
{
    int dx = toPos.x - fromPos.x;
    int dy = toPos.y - fromPos.y;
    if (dx == 0 && dy == 0) return -1;
    if (std::abs(dx) > std::abs(dy)) {
        return dx > 0 ? Otc::East : Otc::West;
    } else {
        return dy > 0 ? Otc::South : Otc::North;
    }
}

std::string HelperCore::numberToOrdinal(int n)
{
    int lastDigit = n % 10;
    int lastTwoDigits = n % 100;
    std::string suffix = "th";
    if (lastTwoDigits < 11 || lastTwoDigits > 13) {
        if (lastDigit == 1) suffix = "st";
        else if (lastDigit == 2) suffix = "nd";
        else if (lastDigit == 3) suffix = "rd";
    }
    return std::to_string(n) + suffix;
}

bool HelperCore::isWithinReach(const Position& playerPos, const Position& targetPos)
{
    return getDistanceBetween(playerPos, targetPos) <= 8 && playerPos.z == targetPos.z;
}

int HelperCore::getAutoTargetModeId(const std::string& modeKey)
{
    static const std::unordered_map<std::string, int> modes = {
        {"A", 1}, {"B", 2}, {"C", 3}, {"D", 4},
        {"E", 5}, {"F", 6}, {"G", 7}, {"H", 8},
        {"I", 9}, {"J", 10}
    };
    auto it = modes.find(modeKey);
    return it != modes.end() ? it->second : 6;
}

std::unordered_map<std::string, int> HelperCore::getAutoTargetModesTable()
{
    return {
        {"A", 1}, {"B", 2}, {"C", 3}, {"D", 4},
        {"E", 5}, {"F", 6}, {"G", 7}, {"H", 8},
        {"I", 9}, {"J", 10}
    };
}
