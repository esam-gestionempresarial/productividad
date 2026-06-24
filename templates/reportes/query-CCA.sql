SELECT
    /* ── Identificador Adaptado CCA ── */
    CASE
        WHEN c.id IN (6,7) THEN CONCAT_WS('-', 'CAR', p.id)
        WHEN c.id IN (10,48) THEN CONCAT_WS('-', 'CFC', p.id)
        WHEN c.id IN (5,8,9,20) AND DATEDIFF(p.fecha_fin, p.fecha_inicio) < 90 THEN CONCAT_WS('-', 'CCC', p.id)
        WHEN c.id IN (5,8,9,20) AND DATEDIFF(p.fecha_fin, p.fecha_inicio) >= 90 THEN CONCAT_WS('-', 'CCL', p.id)
        WHEN c.nombre = 'Pre universitarios' OR c.nombre LIKE '%Pre%universitario%' THEN CONCAT_WS('-', 'PRU', p.id)
        ELSE CONCAT_WS('-', 'CCA', p.id)
    END AS Id_CCA,
    IFNULL(p.codigo, 'sin definir') AS cod_contable,
    i.id AS Id_inscripcion,
    p.nombre_compuesto AS Programa,
    p.gestion,
    s.nombre AS Sede,
    /* ── Clasificación de programas ── */
    CASE
        WHEN c.id IN (6,7) THEN 'Carreras'
        WHEN c.id IN (10,48) THEN 'Cursos de formación continua'
        WHEN c.id IN (5,8,9,20) AND DATEDIFF(p.fecha_fin, p.fecha_inicio) < 90 THEN 'Cursos de capacitación (corto alcance)'
        WHEN c.id IN (5,8,9,20) AND DATEDIFF(p.fecha_fin, p.fecha_inicio) >= 90 THEN 'Cursos de capacitación (largo alcance)'
        WHEN c.nombre = 'Pre universitarios' OR c.nombre LIKE '%Pre%universitario%' THEN 'Pre universitarios'
        ELSE 'Sin clasificar'
    END AS Tipo,
    CONCAT_WS(' ', p3.pri_apellido, p3.seg_apellido, p3.nombres) AS ALUMNO,
    p3.num_doc AS CI,
    i.fecha_registro AS Fecha_Registro
    /* ── Fechas de Control Financiero ── */
    DATE(IFNULL(MIN(kardex.fecha_primera_cuota), '1900-01-01')) AS fecha_primera_cuota,
    DATE(IFNULL(MAX(kardex.fecha_pago_max), '1900-01-01')) AS fecha_ultimo_pago,
    /* ── Parametro Inscripcion (Reglas por montos globales) ── */
    /* ── Parametro Inscripcion (Blindado y sin filtraciones del portal) ── */
    CASE
        WHEN IFNULL(SUM(kardex.total_formativo_cuota), 0) <= 0 THEN 'Prospecto'
        -- Pre universitarios
        WHEN (c.nombre = 'Pre universitarios' OR c.nombre LIKE '%Pre%universitario%') AND SUM(kardex.total_formativo_cuota) >= 500 THEN 'Inscrito'
        WHEN (c.nombre = 'Pre universitarios' OR c.nombre LIKE '%Pre%universitario%') THEN 'Pre inscrito'
        -- Capacitación corto alcance
        WHEN (c.id IN (5,8,9,20) AND DATEDIFF(p.fecha_fin, p.fecha_inicio) < 90) AND SUM(kardex.total_formativo_cuota) >= 750 THEN 'Inscrito'
        WHEN (c.id IN (5,8,9,20) AND DATEDIFF(p.fecha_fin, p.fecha_inicio) < 90) THEN 'Pre inscrito'
        -- Capacitación largo alcance
        WHEN (c.id IN (5,8,9,20) AND DATEDIFF(p.fecha_fin, p.fecha_inicio) >= 90) AND SUM(kardex.total_formativo_cuota) >= 1000 THEN 'Inscrito'
        WHEN (c.id IN (5,8,9,20) AND DATEDIFF(p.fecha_fin, p.fecha_inicio) >= 90) THEN 'Pre inscrito'
        -- Formación continua
        WHEN c.id IN (10,48) AND SUM(kardex.total_formativo_cuota) >= 350 THEN 'Inscrito'
        WHEN c.id IN (10,48) THEN 'Pre inscrito'
        -- Si pasa algo extraño con los montos o nulos, se va a 'sin definir'
        ELSE 'sin definir'
    END AS Parametro_Inscripcion,
    /* ── ESTADO FINANCIERO GLOBAL CCA ── */
    IFNULL(kardex.plan_pago, '-') AS plan_pago,
    IF(MAX(kardex.es_contado) = 1, 'Contado', 'Crédito') AS tipo_plan_pago,
    IFNULL(SUM(kardex.total_formativo_cuota), 0) AS monto_total_pagado,
    IFNULL(SUM(CASE WHEN kardex.saldo > 0 THEN kardex.saldo ELSE 0 END), 0) AS saldo_total_pendiente,
    IFNULL(SUM(IFNULL(kardex.monto_liquidado, 0)), 0) AS monto_total_liquidado
FROM inscripciones i
INNER JOIN programas p ON p.id = i.idprograma
INNER JOIN postgrados p2 ON p2.id = p.idpostgrado
INNER JOIN categorias c ON c.id = p2.idcategoria
INNER JOIN productionadminesamdb.personas p3 ON p3.id = i.idestudiante
INNER JOIN productionadminesamdb.sedes s ON s.id = p.idsede
INNER JOIN estados_inscripcion ei ON ei.id = i.estado_ins
/* ════════════════════════════════════════════════════
   SUBQUERY KARDEX ADAPTADA Y OPTIMIZADA
   ════════════════════════════════════════════════════ */
LEFT JOIN (
    SELECT
        plan_actualizado.id,
        plan_actualizado.inscripcion_id,
        plan_actualizado.plan_pago,
        IF(UPPER(plan_actualizado.plan_pago) LIKE '%CONTADO%', 1, 0) AS es_contado,
        -- Total pagado real por cuota (monto base depositado + regularizaciones/compensaciones)
        (IFNULL(SUM(IFNULL(dpi.monto, 0)), 0) + IFNULL(plan_actualizado.monto_regularizado, 0) + IFNULL(plan_actualizado.monto_compensacion, 0)) AS total_formativo_cuota,
        -- Saldo restante por cuota
        (plan_actualizado.monto - plan_actualizado.descuento - IFNULL(SUM(IFNULL(dpi.monto, 0)), 0)) AS saldo,
        plan_actualizado.monto_liquidado,
        MAX(dpi.fecha_registro_pago) AS fecha_pago_max,
        -- Identificamos la fecha programada para la primera cuota
        MIN(IF(plan_actualizado.nro_cuota = 1, plan_actualizado.fecha_pago, NULL)) AS fecha_primera_cuota
    FROM (
        SELECT
            pp.id,
            pp.nro_cuota,
            pp.fecha_pago,
            pp.inscripcion_id,
            pcp.nombre AS plan_pago,
            pp.monto,
            SUM(IF(m.tipo_descuento_id = 2, ppd.monto, 0)) AS monto_descuento,
            SUM(IF(m.tipo_descuento_id = 1, ppd.monto, 0)) AS monto_regularizado,
            SUM(IF(m.tipo_descuento_id = 4, ppd.monto, 0)) AS monto_compensacion,
            SUM(IF(m.tipo_descuento_id = 3, ppd.monto, 0)) AS monto_liquidado,
            SUM(IFNULL(ppd.monto, 0)) AS descuento
        FROM plan_pagos pp
        INNER JOIN inscripciones i ON pp.inscripcion_id = i.id
        INNER JOIN plan_cobros_programa pcp ON pcp.id = i.plan_cobro_programa_id
        LEFT JOIN plan_pago_descuento ppd ON pp.id = ppd.plan_pago_id AND ppd.fecha_registro < CURRENT_DATE
        LEFT JOIN descuentos d ON d.id = ppd.descuento_id
        LEFT JOIN motivos m ON m.id = d.motivo_id
        WHERE pp.nro_cuota >= 1
        GROUP BY pp.id, pp.nro_cuota, pp.fecha_pago, pp.inscripcion_id, pcp.nombre, pp.monto
    ) plan_actualizado
    LEFT JOIN detalle_pagos_inscripcion dpi ON plan_actualizado.id = dpi.cuota_id AND dpi.estado = 1
    GROUP BY plan_actualizado.id
) kardex ON kardex.inscripcion_id = i.id
WHERE ei.id IN (0,1,2,3,4,5)
  -- Filtro de Categorías CCA
  AND (c.id IN (5,6,7,8,9,10,20,48) OR c.nombre = 'Pre universitarios' OR c.nombre LIKE '%Pre%universitario%')
  -- Sedes exclusivas de CCA
  AND s.id IN (9,10,48,79,110,111,112,115,116,117)
GROUP BY i.id;

