---@type table Store module; the table returned at end of file. The only file that talks SQL;
---callers get and hand over decoded Lua tables.
local store = {}

---Create the tables if they don't exist, so the resource is drop-in. Run once at boot.
function store.ensureSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS trapphone_phones (
            id         VARCHAR(48) NOT NULL,
            number     VARCHAR(16) NOT NULL,
            owner      VARCHAR(64) NULL,
            data       LONGTEXT    NULL,
            updated_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY trapphone_phones_number (number)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS trapphone_relations (
            owner VARCHAR(64) NOT NULL,
            kind  VARCHAR(16) NOT NULL,
            k     VARCHAR(64) NOT NULL,
            v     INT         NOT NULL DEFAULT 0,
            PRIMARY KEY (owner, kind, k)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

---One phone's stored row, decoded (nil when the id is unknown).
---@param id string phone id
---@return { id: string, number: string, owner: string|nil, data: table }|nil row
function store.loadPhone(id)
    local row = MySQL.single.await('SELECT id, number, owner, data FROM trapphone_phones WHERE id = ?', { id })
    if not row then return nil end

    row.data = row.data and json.decode(row.data) or {}

    return row
end

---The phone id a number belongs to (nil when the number is not a trap phone).
---@param number string burner number
---@return string|nil id
function store.phoneIdByNumber(number)
    return MySQL.scalar.await('SELECT id FROM trapphone_phones WHERE number = ?', { number })
end

---Whether a burner number is already taken.
---@param number string burner number
---@return boolean taken
function store.numberTaken(number)
    return MySQL.scalar.await('SELECT 1 FROM trapphone_phones WHERE number = ?', { number }) ~= nil
end

---Persist a phone (upsert).
---@param id string phone id
---@param number string burner number
---@param owner string|nil character id of whoever last held it
---@param data table the phone's whole state
function store.savePhone(id, number, owner, data)
    MySQL.prepare.await(
        'INSERT INTO trapphone_phones (id, number, owner, data) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner = VALUES(owner), data = VALUES(data)',
        { id, number, owner, json.encode(data) })
end

---Persist a phone without waiting for the database. For resource stop only.
---@param id string phone id
---@param number string burner number
---@param owner string|nil character id of whoever last held it
---@param data table the phone's whole state
function store.savePhoneNow(id, number, owner, data)
    MySQL.prepare(
        'INSERT INTO trapphone_phones (id, number, owner, data) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner = VALUES(owner), data = VALUES(data)',
        { id, number, owner, json.encode(data) })
end

---Every relation of one kind an owner holds, as a key -> value map.
---@param owner string character id, or a job name for shared job standing
---@param kind string 'ped' | 'gang' | 'protect'
---@return table<string, integer> values
function store.loadRelations(owner, kind)
    local rows = MySQL.query.await('SELECT k, v FROM trapphone_relations WHERE owner = ? AND kind = ?', { owner, kind })
    local out = {}

    for i = 1, #(rows or {}) do
        out[rows[i].k] = rows[i].v
    end

    return out
end

---Persist one relation value (upsert).
---@param owner string character id or job name
---@param kind string relation kind
---@param key string what the relation is with
---@param value integer the value to store
function store.saveRelation(owner, kind, key, value)
    MySQL.prepare.await(
        'INSERT INTO trapphone_relations (owner, kind, k, v) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)',
        { owner, kind, key, value })
end

return store
