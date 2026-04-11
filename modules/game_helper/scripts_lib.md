# Biblioteca de Scripts (Bot Helper)

Funções disponíveis na aba **Scripts** e em waypoints **Action** do cavebot.

---

### 1. `say(texto)`

Envia mensagem no canal de NPCs ("hi", "trade", etc.).

```lua
say("hi")
say("trade")
```

---

### 2. `wait(tempo)`

Pausa em **milissegundos**. Máximo 5000 ms por chamada.

```lua
say("hi")
wait(500)
say("trade")
```

---

### 3. `useItem(itemId)`

Usa um item do inventário pelo ID.

```lua
useItem(2274)
useItem(7618)
```

---

### 4. `moveItem(containerId, slot, toX, toY, toZ, count)`

Move item de um container para uma posição no mapa. `count` opcional (padrão 1).

```lua
moveItem(0, 2, 100, 100, 7, 5)
```

---

### 5. `moveItemById(itemId, toX, toY, toZ, count)`

Procura o item pelo ID em qualquer container aberto e move para o mapa. `count` opcional.

```lua
local pos = getPosition()
if pos then moveItemById(2274, pos.x, pos.y, pos.z, 10) end
```

---

### 6. `getFreeCapacity()`

Retorna a capacidade livre em **oz**, ou `nil`.

```lua
local cap = getFreeCapacity()
```

---

### 7. `hasEnoughCap(minCap)`

Retorna `true` se a capacidade livre for ≥ `minCap`.

```lua
if not hasEnoughCap(10000) then return end
useItem(63338)
```

---

### 8. `getItemCount(itemId)`

Retorna o total de unidades do item (inventário + containers abertos).

```lua
if getItemCount(2274) < 10 then
  say("hi"); wait(500); say("trade"); wait(500)
  npcTradeBuy(2274, 100)
end
```

---

### 9. Funções do jogador

Retornam `nil` se o jogador não estiver disponível.

| Função | Retorno |
|--------|---------|
| `getHealth()` | Vida atual |
| `getMana()` | Mana atual |
| `getMaxHealth()` | Vida máxima |
| `getMaxMana()` | Mana máxima |
| `getHealthPercent()` | Vida % (0–100) |
| `getManaPercent()` | Mana % (0–100) |
| `getLevel()` | Nível |
| `getPosition()` | `{ x, y, z }` |

Constantes de direção: `DirectionNorth` (0), `DirectionEast` (1), `DirectionSouth` (2), `DirectionWest` (3).

```lua
if getHealthPercent() and getHealthPercent() < 50 then useItem(7618) end
```

---

### 10. `modalAnswer(id, buttonId, choice)`

Responde janela modal (ex.: "Select an option"). `buttonId` 255 = padrão.

```lua
modalAnswer(1, 1, 0)
```

---

### 11. `simulateKey(keyCode)`

Simula tecla no widget com foco. Constantes: `KeyEnter`, `KeyEscape`, `KeyUp`, `KeyDown`, `KeyLeft`, `KeyRight`, `KeySpace`.

```lua
useItem(63338)
scheduleEvent(function() simulateKey(KeyEnter) end, 500)
```

---

### 12. `clickSelectButton()`

Clica no botão "Select" / "Selecionar" na interface (modais, diálogos).

```lua
useItem(63338)
scheduleEvent(function() clickSelectButton() end, 500)
```

---

### 13. `npcTradeBuy(itemRef, quantity)`

Compra na janela de trade do NPC (aba **Buy** aberta). `itemRef` = nome ou ID do item.

```lua
npcTradeBuy("avalanche rune", 100)
npcTradeBuy(2274, 50)
```

---

### 14. `npcTradeSell(itemRef, quantity)`

Vende na janela de trade (aba **Sell** aberta).

```lua
npcTradeSell("avalanche rune", 100)
```

---

### 15. `scheduleEvent(func, delay)`

Agenda a execução de `func` após `delay` milissegundos.

```lua
scheduleEvent(function() say("trade") end, 400)
```

---

### 16. `gotoid(id)`

Define o waypoint atual do cavebot para o índice `id` (1-based). Só tem efeito com cavebot ligado.

```lua
gotoid(10)
```

---

