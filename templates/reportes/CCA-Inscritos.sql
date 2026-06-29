SELECT
    un.nombre AS UNIDAD,
    s.nombre AS SEDE,
    CONCAT_WS(' ', p2.nombres, p2.pri_apellido, p2.seg_apellido) AS ASESOR,
    p2.num_doc AS CI_ASESOR,
    i.id AS ID_INSCRIPCION,
    CONCAT_WS(' ', p3.nombres, p3.pri_apellido, p3.seg_apellido) AS ALUMNO,
    p3.num_doc AS CI_ALUMNO,
    c.nombre AS TIPO,
    p.codigo AS COD_CONTABLE,
    p.nombre_compuesto AS PROGRAMA,
    pcp.nombre AS PLAN_PAGO,
    MAX(cp.cuotas) AS NRO_CUOTAS,
    MAX(kardex.monto_total_plan) AS MONTO_TOTAL,
    MAX(kardex.fecha_primer_pago) AS FECHA_PAGO_1RA_CUOTA,
    /* ── LÓGICA DE ESTADO CCA ACTUALIZADA ── */
    CASE
        -- Regla General: Sin pagos es Prospecto
        WHEN MAX(kardex.total_cuotas) = 0 THEN 'Prospecto'
        -- Carreras (IDs: 6,7)
        WHEN MAX(c.id) IN (6,7) THEN
            IF(MAX(kardex.total_cuotas) >= 360, 'Inscrito', 'Pre inscrito')
        -- Preuniversitarios (Por coincidencia de nombre)
        WHEN MAX(c.nombre) LIKE '%Pre%universitario%' THEN
            IF(MAX(kardex.total_cuotas) >= 500, 'Inscrito', 'Pre inscrito')
        -- Cursos de formación continua (Solo ID: 10)
        WHEN MAX(c.id) = 10 THEN
            IF(MAX(kardex.total_cuotas) >= 350, 'Inscrito', 'Pre inscrito')
        -- Cursos de capacitación (corto alcance < 90 días) (Por nombre, excluyendo ID 10)
        WHEN MAX(c.nombre) LIKE '%Curso%' AND MAX(c.id) != 10 AND DATEDIFF(MAX(p.fecha_fin), MAX(p.fecha_inicio)) < 90 THEN
            IF(MAX(kardex.total_cuotas) >= 750, 'Inscrito', 'Pre inscrito')
        -- Cursos de capacitación (largo alcance >= 90 días) (Por nombre, excluyendo ID 10)
        WHEN MAX(c.nombre) LIKE '%Curso%' AND MAX(c.id) != 10 AND DATEDIFF(MAX(p.fecha_fin), MAX(p.fecha_inicio)) >= 90 THEN
            IF(MAX(kardex.total_cuotas) >= 1000, 'Inscrito', 'Pre inscrito')
        ELSE 'Sin Estado'
    END AS ESTADO_CCA,
    MAX(kardex.monto_total_cancelado) AS MONTO_CANCELADO,
    MAX(kardex.monto_total_saldo) AS SALDO,
    DATE(i.fecha_registro) AS FECHA_REGISTRO,
    i2.abreviatura AS CONVENIO
FROM productionacademicoesamdb.inscripciones i
INNER JOIN productionacademicoesamdb.programas p ON i.idprograma = p.id
INNER JOIN productionacademicoesamdb.postgrados p4 ON p.idpostgrado = p4.id
INNER JOIN productionacademicoesamdb.categorias c ON p4.idcategoria = c.id
INNER JOIN productionacademicoesamdb.plan_cobros_programa pcp ON i.plan_cobro_programa_id = pcp.id
INNER JOIN productionacademicoesamdb.cobros_programa cp ON pcp.id = cp.plan_cobro_programa_id
INNER JOIN productionadminesamdb.sedes s ON p.idsede = s.id
INNER JOIN productionadminesamdb.personas p2 ON i.idasesor = p2.id
INNER JOIN productionadminesamdb.personas p3 ON i.idestudiante = p3.id
INNER JOIN productionadminesamdb.unidad_negocio un ON s.unidad_negocio = un.id
INNER JOIN productionadminesamdb.instituciones i2 ON p.iduniversidad = i2.id
/* ════════════════════════════════════════════════════
   SUBQUERY KARDEX: Agrupación financiera por inscrito
   ════════════════════════════════════════════════════ */
INNER JOIN (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_total_plan,
        SUM(IFNULL(dpi.monto, 0)) AS monto_total_cancelado,
        SUM(pp.monto - IFNULL(dpi.monto, 0)) AS monto_total_saldo,
        SUM(CASE WHEN pp.nro_cuota > 0 THEN IFNULL(dpi.monto, 0) ELSE 0 END) AS total_cuotas,
        DATE(MIN(CASE WHEN dpi.estado = 1 THEN pi2.fecha_registro END)) AS fecha_primer_pago
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN productionacademicoesamdb.detalle_pagos_inscripcion dpi ON pp.id = dpi.cuota_id AND dpi.estado = 1
    LEFT JOIN productionacademicoesamdb.pagos_inscripcion pi2 ON pi2.id = dpi.pagos_inscripcion_id
    GROUP BY pp.inscripcion_id
) kardex ON kardex.inscripcion_id = i.id
/* IDs Sedes de CCA */
WHERE s.id IN (9,10,48,79)
  AND i.fecha_registro BETWEEN '2026-01-01 00:00:00' AND '2026-05-31 23:59:59'
GROUP BY i.id
ORDER BY i.fecha_registro ASC;