-- Exemple de migration (module postgres). Une fois appliquée, ne jamais la modifier : en créer une nouvelle.
CREATE TABLE IF NOT EXISTS items (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        text        NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS items_created_at_idx ON items (created_at);
