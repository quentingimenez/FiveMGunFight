-- =============================================================================
--  gf_core - MARQUEUR DE PLANTAGE (module client pur)
--
--  Un marqueur KVP est posé avant un chargement sensible et retiré après. S'il
--  est encore présent au démarrage suivant, le chargement a fait planter le jeu :
--  la ressource concernée est mise de côté pour cette version, puis le marqueur
--  est effacé. Ce module est exposé en global pour être repris par gf_core et
--  gf_thumbs (deux anciens blocs dupliqués, cf. chantier C24).
--
--  Aucune native FiveM, aucun print, aucun événement, aucune horloge : les accès
--  KVP sont fournis par l'appelant sous la forme d'une table de trois fonctions
--  nommées (get/set/del), et non d'arguments positionnels fragiles.
-- =============================================================================

-- luacheck: globals CrashMarker
CrashMarker = {}

local M = CrashMarker

-- Crée un marqueur.
--   cleMarqueur       : clé KVP du marqueur (« chargement en cours »).
--   prefixeMiseDeCote : préfixe des clés KVP des mises de côté.
--   kvp               : { get = fn(cle), set = fn(cle, valeur), del = fn(cle) }.
-- new ne valide rien, n'écrase rien et n'appelle aucun natif : en jeu, l'appelant
-- fournit ses propres fonctions de lecture, d'écriture et d'effacement de KVP.
function M.new(cleMarqueur, prefixeMiseDeCote, kvp)
    local marqueur = {
        cle = cleMarqueur,
        prefixe = prefixeMiseDeCote,
        kvp = kvp,
    }

    -- Relève un plantage éventuel. Sans marqueur, ne fait rien et renvoie nil
    -- (une seule valeur). Sinon, écrit la mise de côté, efface le marqueur et
    -- renvoie ref, version (deux valeurs), dans cet ordre d'opérations.
    function marqueur:recover()
        local valeur = self.kvp.get(self.cle)
        if valeur == nil or valeur == '' then
            return nil
        end

        local ref, version = valeur:match('^([^@]+)@(.*)$')
        ref = ref or valeur
        version = version or '0'
        self.kvp.set(self.prefixe .. ref, version)
        self.kvp.del(self.cle)
        return ref, version
    end

    -- Pose le marqueur avant un chargement ; une version absente vaut '0'.
    function marqueur:begin(ref, version)
        self.kvp.set(self.cle, ref .. '@' .. tostring(version or '0'))
    end

    -- Retire le marqueur après un chargement réussi.
    function marqueur:finish()
        self.kvp.del(self.cle)
    end

    -- Vrai si cette référence est déjà mise de côté pour cette version.
    function marqueur:isBad(ref, version)
        return self.kvp.get(self.prefixe .. ref) == tostring(version or '0')
    end

    -- Lève la mise de côté (le modèle a depuis été rejoué avec succès).
    function marqueur:clear(ref)
        self.kvp.del(self.prefixe .. ref)
    end

    return marqueur
end
