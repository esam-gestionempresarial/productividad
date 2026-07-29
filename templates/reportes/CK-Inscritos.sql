WITH
-- CTE 0: Subconsulta pre-agrupada por cuota_id para evitar multiplicación de montos (Fan-out bug)
cte_pagos_info AS (
    SELECT
        dpi.cuota_id,
        MAX(dpi.fecha_registro_pago) AS fecha_pago,
        MAX(pi.nro_recibo) AS nro_recibo
    FROM productionacademicoesamdb.detalle_pagos_inscripcion dpi
    INNER JOIN productionacademicoesamdb.pagos_inscripcion pi
           ON pi.id = dpi.pagos_inscripcion_id AND pi.estado = 1
    WHERE dpi.estado = 1
    GROUP BY dpi.cuota_id
),
-- 1) Mensualidad, cuota 1 — aplica a Estimulación Temprana (34), PROGRAMAS (14) y Kinder (35) [Concepto 27]
cte_mensualidad_c1 AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_mensualidad_c1,
        SUM(pp.monto - pp.saldo) AS cancelado_mensualidad_c1,
        SUM(pp.saldo) AS saldo_mensualidad_c1,
        MAX(pinfo.fecha_pago) AS fecha_ultimo_pago_mensualidad,
        MAX(pinfo.nro_recibo) AS nro_recibo_mensualidad
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN cte_pagos_info pinfo ON pinfo.cuota_id = pp.id
    WHERE pp.concepto_pago_id = 27 AND pp.nro_cuota = 1
    GROUP BY pp.inscripcion_id
),
-- 2) Saldo total de cursos — aplica a CURSOS (13) y TALLERES (12) [Concepto 311]
cte_cursos_total AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_total_cursos,
        SUM(pp.monto - pp.saldo) AS cancelado_total_cursos,
        SUM(pp.saldo) AS saldo_total_cursos,
        MAX(pinfo.fecha_pago) AS fecha_ultimo_pago_cursos
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN cte_pagos_info pinfo ON pinfo.cuota_id = pp.id
    WHERE pp.concepto_pago_id = 311
    GROUP BY pp.inscripcion_id
)
SELECT
    un.nombre AS UNIDAD,
    s.nombre AS SEDE,
    CONCAT_WS(' ', p3.nombres, p3.pri_apellido, p3.seg_apellido) AS ASESOR,
    p3.num_doc AS CI_ASESOR,
    CONCAT_WS(' ', p4.nombres, p4.pri_apellido, p4.seg_apellido) AS ALUMNO,
    p4.num_doc AS CI_ALUMNO,
    c.nombre AS TIPO_PROGRAMA,
    i.id AS ID_INSCRIPCION,
    p.codigo AS COD_CONTABLE,
    p.nombre_compuesto AS PROGRAMA,
    p.id AS ID_PROGRAMA,
    IF(UPPER(pcp.nombre) LIKE '%CONTADO%', 'Contado', 'Crédito') AS TIPO_PLAN_PAGO,
    CASE WHEN c.id IN (12, 13) THEN 1 ELSE 0 END AS ES_CURSO,
    -- Columnas financieras completas para Mensualidad Cuota 1 (Concepto 27)
    IFNULL(m1.monto_mensualidad_c1, 0) AS MONTO_MENSUALIDAD_CUOTA1,
    IFNULL(m1.cancelado_mensualidad_c1, 0) AS CANCELADO_MENSUALIDAD_CUOTA1,
    IFNULL(m1.saldo_mensualidad_c1, 0) AS SALDO_MENSUALIDAD_CUOTA1,
    -- Columnas financieras completas para Cursos Total (Concepto 311)
    IFNULL(ct.monto_total_cursos, 0) AS MONTO_TOTAL_PLAN,
    IFNULL(ct.cancelado_total_cursos, 0) AS CANCELADO_TOTAL_PLAN,
    IFNULL(ct.saldo_total_cursos, 0) AS SALDO_TOTAL_PLAN,
    -- Fecha de pago que rige la productividad
    CASE
        WHEN c.id IN (12, 13) THEN ct.fecha_ultimo_pago_cursos
        WHEN c.id IN (14, 34, 35) THEN m1.fecha_ultimo_pago_mensualidad
        ELSE NULL
    END AS FECHA_PAGO_PRODUCTIVIDAD,
    -- Condición de inscrito (Saldo 0 dependiendo de la categoría)
    CASE
        WHEN c.id IN (12, 13) 
            THEN IF(IFNULL(ct.saldo_total_cursos, 1) = 0, 'INSCRITO', 'NO INSCRITO')
        WHEN c.id IN (14, 34, 35) 
            THEN IF(IFNULL(m1.saldo_mensualidad_c1, 1) = 0, 'INSCRITO', 'NO INSCRITO')
        ELSE 'NO IDENTIFICADO'
    END AS CONDICION_PRODUCTIVIDAD,
    CASE
        WHEN i.estado_ins = 0 THEN 'PRE-INSCRITO'
        WHEN i.estado_ins = 1 THEN 'INSCRITO'
        WHEN i.estado_ins = 2 THEN 'RETIRADO'
        WHEN i.estado_ins = 3 THEN 'CAMBIADO'
        WHEN i.estado_ins = 4 THEN 'CONGELADO'
        WHEN i.estado_ins = 5 THEN 'PAGADO'
        ELSE 'NO IDENTIFICADO'
    END AS ESTADO_INSCRIPCION,
    CASE MONTH(
        CASE
            WHEN c.id IN (12, 13) THEN ct.fecha_ultimo_pago_cursos
            WHEN c.id IN (14, 34, 35) THEN m1.fecha_ultimo_pago_mensualidad
        END
    )
        WHEN 1 THEN 'ENERO'
        WHEN 2 THEN 'FEBRERO'
        WHEN 3 THEN 'MARZO'
        WHEN 4 THEN 'ABRIL'
        WHEN 5 THEN 'MAYO'
        WHEN 6 THEN 'JUNIO'
        WHEN 7 THEN 'JULIO'
        WHEN 8 THEN 'AGOSTO'
        WHEN 9 THEN 'SEPTIEMBRE'
        WHEN 10 THEN 'OCTUBRE'
        WHEN 11 THEN 'NOVIEMBRE'
        WHEN 12 THEN 'DICIEMBRE'
    END AS MES
FROM productionacademicoesamdb.inscripciones i
INNER JOIN productionacademicoesamdb.programas p ON p.id = i.idprograma
INNER JOIN productionacademicoesamdb.postgrados p2 ON p2.id = p.idpostgrado
INNER JOIN productionacademicoesamdb.categorias c ON c.id = p2.idcategoria
LEFT JOIN  productionacademicoesamdb.plan_cobros_programa pcp ON pcp.id = i.plan_cobro_programa_id
INNER JOIN productionadminesamdb.personas p4 ON p4.id = i.idestudiante
LEFT JOIN  productionadminesamdb.personas p3 ON p3.id = i.idasesor
INNER JOIN productionadminesamdb.sedes s ON s.id = p.idsede
LEFT JOIN  productionadminesamdb.unidad_negocio un ON un.id = s.unidad_negocio
LEFT JOIN  productionadminesamdb.instituciones i2 ON i2.id = p.iduniversidad
LEFT JOIN  cte_mensualidad_c1 m1 ON m1.inscripcion_id = i.id
LEFT JOIN  cte_cursos_total ct ON ct.inscripcion_id = i.id
WHERE s.id IN (11, 12, 13, 47, 81)
  AND (
        CASE
            WHEN c.id IN (12, 13) THEN ct.fecha_ultimo_pago_cursos
            WHEN c.id IN (14, 34, 35) THEN m1.fecha_ultimo_pago_mensualidad
        END
      ) BETWEEN '2026-01-01 00:00:00' AND '2026-06-30 23:59:59'
ORDER BY i.id;