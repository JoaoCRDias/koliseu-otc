## O que fiz

Integrei o PR #1604 do otclient (by kokekanon) que traz o módulo `game_npctrader` com a nova janela de NPC em HTML, suporte a protocolo 15.21+ (NPC trader HTML, client events, effect source opacity, cyclopedia expandido, task board). Tudo alinhado para funcionar nativamente com meu servidor Canary 15.23.

---

## Commits e o que cada um faz

### `6fdd22ee8` — Fix prey reroll price desync e quest tracker format
- O cliente lia 10 bytes a mais no `parsePreyRerollPrice` (U32+U32+U8+U8 de task hunting prices) que o servidor Canary nunca enviava, causando desync massivo que corrompia prey, bounty tasks, weekly tasks e gerava "Unhandled opcode 0x03"
- Corrigi `sendRequestTrackerQuestLog` para enviar o formato que o Canary espera: `U8 missionCount + [U16 missionId]* + U8 autoTrack + U8 autoUntrack` (não quest names)
- `levelPercent` corrigido de `uint8_t` para `uint16_t` em `localplayer.h`, `localplayer.cpp` e `protocolgameparse.cpp` (servidor envia `levelPercent * 100` como U16, range 0-10000)
- Resource types alinhados: `RESOURCE_BOUNTY_POINTS = 86`, `RESOURCE_SOULSEALS_POINTS = 87` enviados como U32; demais como U64

### `f444a70f8` — Fix bounty selectTask e weekly difficulty modal loop
- O cliente enviava `raceId` (ex: 2547) onde o servidor esperava `taskIndex` (0-8) no bounty selectTask. Corrigi extraindo o taskIndex dos dados do servidor
- `weeklyProgressFinished == 0` era interpretado como `difficulty=0`, re-disparando o modal após gerar tarefas. Corrigi usando `unlockedDifficulty` diretamente

### `3235fbf14` — Fix module name game_npctrade -> game_npctrader
- O PR #1604 renomeou o módulo de `game_npctrade` para `game_npctrader`, mas 4 arquivos ainda referenciavam o nome antigo. Corrigi todas as referências

### `bfbb9051e` — Align parseNpcChatWindow com formato Canary
- O parser C++ do opcode 0x1C (NPC Chat Window) foi alinhado com o formato exato que o servidor Canary envia: `U8 status + U8 npcCount + [U32 npcId]* + U8 buttonCount + [U8 id + String text]*`

### `32bbac992` — Fix NPC dialog open/close flow
- `conversationId=0` (close) mapeia naturalmente para `npcCount=0` e `buttonCount=0` no formato Canary, dispensando tratamento especial

### `19a82959d` — Align NPC dialog com PR #1604 1:1
- Alinhei o código do NPC dialog exatamente como no PR #1604 original, mantendo compatibilidade com o formato binário do Canary

### `8ea33ce25` — Fix NPC trader window: eventos, janela duplicada, trade items
Este foi o commit final que fez tudo funcionar de verdade:

**Root cause encontrado:** O sistema `Controller:onGameStart()` nunca disparava para o módulo `game_npctrader`, então nenhum evento Lua era registrado. O `connect(g_game, { onGameStart = ... })` no `Controller:init()` não funcionava para este módulo. Solução: registrei todos os eventos diretamente em `onInit()` ao invés de depender do `onGameStart`.

**Eventos registrados em onInit:**
- `onNpcChatWindow` - abre a janela de diálogo HTML do NPC
- `onOpenNpcTrade` - recebe os itens do shop do servidor
- `onPlayerGoods` - atualiza gold e itens do jogador
- `onCloseNpcTrade` - fecha a janela e limpa estado
- `onTalk` - mensagens do NPC no chat embutido

**Fix janela duplicada:**
- `_flushNpcWindowOpen` agora verifica se a janela já existe antes de criar outra
- `onNpcChatWindow` pula se a janela já está visível (evita re-criação quando o servidor re-envia o opcode)
- `reloadButtonsUI` recria apenas os botões dinamicamente sem re-criar a janela HTML inteira (antes chamava `loadHtml` que destruía e recriava tudo, causando duplicação e perda de referências)

**Fix trade items:**
- `isNewSession` não era mais sobrescrito antes da checagem (o `isTradeOpen = true` foi movido para depois)
- `itemBatchSize` e outras variáveis de sessão são inicializadas corretamente

**Outros:**
- Opção `displayNpcDialogWindow` adicionada em `data_options.lua` (elimina warning no console)
- Todos os debug prints removidos

---

## Arquivos modificados (21 arquivos, +3377 -753 linhas)

### C++ (src/client/)
- `protocolgameparse.cpp` — parseNpcChatWindow, parsePreyRerollPrice, parsePlayerStats (levelPercent U16), parseResourceBalance, parseOpenNpcTrade
- `protocolgamesend.cpp` — sendRequestTrackerQuestLog, sendBountyTaskAction (taskIndex)

### Lua — NPC Trader (modules/game_npctrader/)
- `game_npctrader.lua` — Eventos registrados em onInit, fluxo completo de open/close
- `controllers/npc_dialog.lua` — onNpcChatWindow, initNpcWindow, reloadButtonsUI, debounce
- `controllers/npc_trader.lua` — onOpenNpcTrade, setTradeMode, filterTradeList, loadNextBatch
- `controllers/npc_options.lua` — Sort/filter/options
- `controllers/npc_legacy_ui.lua` — Legacy trade window fallback
- `controllers/npc_trade_tooltip.lua` — Tooltip de itens (novo)
- `npc_trade_tooltip.otui` — UI do tooltip (novo)
- `constants/trader_const.lua` — Constantes, presets de botões, keyword map
- `templates/game_npctrader.html` — Template HTML da janela
- `templates/npctrade_legacy.otui` — Template legacy

### Lua — Outros módulos
- `client_options/data_options.lua` — Opção displayNpcDialogWindow
- `game_task_hunt/classes/bounty-tasks.lua` — Fix taskIndex
- `game_task_hunt/classes/weekly-tasks.lua` — Fix difficulty modal
- `game_features/features.lua` — Remoção de features duplicadas
- `game_interface/gameinterface.lua` — Ajustes de compatibilidade
- `game_cyclopedia/` — Ajustes bestiary e items

### Framework (modules/modulelib/)
- `controller.lua` — Sem mudanças funcionais (debugs removidos)

---

## Estado atual

Tudo funcional:
- Login no Canary 15.23
- Inventário, prey, bounty tasks, weekly tasks com difficulty selection
- Soulseal (opcode 0xBA)
- NPC dialog HTML abre ao falar "hi"
- Botões de ação (yes/no/bye/trade) funcionam
- Lista de trade items aparece ao clicar "trade"
- Compra/venda de itens funciona
- Janela legacy fallback disponível

**Pendente:** A aba de categorias/organização dos itens de trade pode precisar de ajustes visuais.
