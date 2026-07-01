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
    p.nombre_compuesto AS CARRERAS,
    pcp.nombre AS PLAN_PAGO,
    MAX(cp.cuotas) AS NRO_CUOTAS,
    MAX(IFNULL(kardex.monto_total_plan, 0)) AS MONTO_TOTAL,
    MAX(kardex.fecha_primer_pago) AS FECHA_PAGO_1RA_CUOTA,
    /* ── LÓGICA DE ESTADO CK (Ciberkids) ── */
    CASE
        WHEN MAX(IFNULL(kardex.total_cuotas, 0)) = 0 THEN 'Prospecto'
        -- Kinder (Filtrado por texto en el nombre de la categoría)
        WHEN MAX(c.nombre) LIKE '%kinder%' THEN
            IF(MAX(IFNULL(kardex.total_cuotas, 0)) >= 600 AND MAX(IFNULL(kardex.pagado_cuota_1, 0)) >= MAX(IFNULL(kardex.monto_cuota_1, 0)), 'Inscrito', 'Pre inscrito')
        -- CDI (ID de categoría 14, siempre que NO sea un Kinder)
        WHEN MAX(c.id) = 14 AND MAX(c.nombre) NOT LIKE '%kinder%' THEN
            IF(MAX(IFNULL(kardex.total_cuotas, 0)) >= 600 AND MAX(IFNULL(kardex.pagado_cuota_1, 0)) >= MAX(IFNULL(kardex.monto_cuota_1, 0)), 'Inscrito', 'Pre inscrito')
        -- Curso de formación continua (IDs de categoría 12 y 13)
        WHEN MAX(c.id) IN (12, 13) THEN
            IF(MAX(IFNULL(kardex.total_cuotas, 0)) >= 120 AND MAX(IFNULL(kardex.pagado_cuota_1, 0)) >= MAX(IFNULL(kardex.monto_cuota_1, 0)), 'Inscrito', 'Pre inscrito')
        ELSE 'Sin Estado'
    END AS ESTADO_CK,
    MAX(IFNULL(kardex.monto_total_cancelado, 0)) AS MONTO_CANCELADO,
    MAX(IFNULL(kardex.monto_total_saldo, 0)) AS SALDO,
    DATE(i.fecha_registro) AS FECHA_REGISTRO,
    i2.abreviatura AS CONVENIO
FROM productionacademicoesamdb.inscripciones i
INNER JOIN productionacademicoesamdb.programas p ON i.idprograma = p.id
-- LEFT JOIN en caso de que programas base (niños) no usen la tabla postgrados
LEFT JOIN productionacademicoesamdb.postgrados p4 ON p.idpostgrado = p4.id
LEFT JOIN productionacademicoesamdb.categorias c ON p4.idcategoria = c.id
LEFT JOIN productionacademicoesamdb.plan_cobros_programa pcp ON i.plan_cobro_programa_id = pcp.id
LEFT JOIN productionacademicoesamdb.cobros_programa cp ON pcp.id = cp.plan_cobro_programa_id
INNER JOIN productionadminesamdb.sedes s ON p.idsede = s.id
INNER JOIN productionadminesamdb.personas p2 ON i.idasesor = p2.id
INNER JOIN productionadminesamdb.personas p3 ON i.idestudiante = p3.id
INNER JOIN productionadminesamdb.unidad_negocio un ON s.unidad_negocio = un.id
-- LEFT JOIN porque Ciberkids seguramente no tiene una universidad asociada
LEFT JOIN productionadminesamdb.instituciones i2 ON p.iduniversidad = i2.id
/* ════════════════════════════════════════════════════
   SUBQUERY KARDEX: Pasado a LEFT JOIN
   ════════════════════════════════════════════════════ */
LEFT JOIN (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_total_plan,
        SUM(IFNULL(dpi.monto, 0)) AS monto_total_cancelado,
        SUM(pp.monto - IFNULL(dpi.monto, 0)) AS monto_total_saldo,
        SUM(CASE WHEN pp.nro_cuota > 0 THEN IFNULL(dpi.monto, 0) ELSE 0 END) AS total_cuotas,
        DATE(MIN(CASE WHEN dpi.estado = 1 THEN pi2.fecha_registro END)) AS fecha_primer_pago,
        MAX(CASE WHEN pp.nro_cuota = 1 THEN pp.monto ELSE 0 END) AS monto_cuota_1,
        SUM(CASE WHEN pp.nro_cuota = 1 THEN IFNULL(dpi.monto, 0) ELSE 0 END) AS pagado_cuota_1
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN productionacademicoesamdb.detalle_pagos_inscripcion dpi ON pp.id = dpi.cuota_id AND dpi.estado = 1
    LEFT JOIN productionacademicoesamdb.pagos_inscripcion pi2 ON pi2.id = dpi.pagos_inscripcion_id
    GROUP BY pp.inscripcion_id
) kardex ON kardex.inscripcion_id = i.id
WHERE s.id IN (11,12,13,47,81)
  AND i.fecha_registro BETWEEN '2026-01-01 00:00:00' AND '2026-05-31 23:59:59'
GROUP BY i.id
ORDER BY i.fecha_registro ASC;