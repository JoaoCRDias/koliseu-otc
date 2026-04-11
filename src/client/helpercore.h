#pragma once

#include <framework/core/clock.h>
#include <framework/global.h>
#include "position.h"
#include <unordered_map>
#include <string>
#include <vector>

 // @bindsingleton g_helperCore
class HelperCore
{
public:
    void clearCooldowns();

    void setSpellCooldown(int spellId, int delay);
    void setSpellCooldownEndTime(int spellId, ticks_t endTime);
    int getSpellCooldown(int spellId);
    bool isSpellOnCooldown(int spellId);

    void setGroupCooldown(int groupId, int delay);
    int getGroupCooldown(int groupId);
    bool isGroupOnCooldown(int groupId);

    void setMultiUseCooldown(int delay);
    bool isMultiUseOnCooldown();

    int translateVocation(int vocation);
    std::vector<int> getClientVocationsForServerVoc(int serverVocId);
    bool canUseByServerVoc(const std::vector<int>& spellVocations, int serverVocId);

    int getDistanceBetween(const Position& p1, const Position& p2);
    bool positionCompare(const Position& p1, const Position& p2);
    int getDirectionTo(const Position& fromPos, const Position& toPos);
    std::string numberToOrdinal(int n);
    bool isWithinReach(const Position& playerPos, const Position& targetPos);

    int getAutoTargetModeId(const std::string& modeKey);
    std::unordered_map<std::string, int> getAutoTargetModesTable();

private:
    std::unordered_map<int, ticks_t> m_spellsCooldown;
    std::unordered_map<int, ticks_t> m_groupsCooldown;
    ticks_t m_multiUseCooldownEnd = 0;
};

extern HelperCore g_helperCore;
