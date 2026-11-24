-- point-in-polygon test for Config.PrisonZone, shared by the client zone check and the server-side backstop
-- pos: anything with x, y, z (vector3 / vector4)
function PrisonZoneContains(pos)
    local pts = Config.PrisonZone.points
    if math.abs(pos.z - pts[1].z) > Config.PrisonZone.thickness / 2 then return false end
    local inside, j = false, #pts
    for i = 1, #pts do
        local a, b = pts[i], pts[j]
        if ((a.y > pos.y) ~= (b.y > pos.y)) and (pos.x < (b.x - a.x) * (pos.y - a.y) / (b.y - a.y) + a.x) then
            inside = not inside
        end
        j = i
    end
    return inside
end
