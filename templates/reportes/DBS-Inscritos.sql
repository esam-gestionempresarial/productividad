WITH
-- CTE 0: Subconsulta pre-agrupada por cuota_id para aislar pagos y evitar multiplicación de montos (Fan-out bug)
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
-- 1) Cuota Inicial (concepto 133, cuota 1)
cte_cuota_inicial AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_cuota_inicial,
        SUM(pp.monto - pp.saldo) AS cancelado_cuota_inicial,
        SUM(pp.saldo) AS saldo_cuota_inicial,
        MAX(pinfo.fecha_pago) AS fecha_primer_pago_inicial,
        MAX(pinfo.nro_recibo) AS nro_recibo_inicial
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN cte_pagos_info pinfo ON pinfo.cuota_id = pp.id
    WHERE pp.concepto_pago_id = 133 AND pp.nro_cuota = 1
    GROUP BY pp.inscripcion_id
),
-- 2) Colegiatura, cuota 1 (concepto 2)
cte_colegiatura_c1 AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_colegiatura_c1,
        SUM(pp.monto - pp.saldo) AS cancelado_colegiatura_c1,
        SUM(pp.saldo) AS saldo_colegiatura_c1,
        MAX(pinfo.fecha_pago) AS fecha_primer_pago_colegiatura,
        MAX(pinfo.nro_recibo) AS nro_recibo_colegiatura
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN cte_pagos_info pinfo ON pinfo.cuota_id = pp.id
    WHERE pp.concepto_pago_id = 2 AND pp.nro_cuota = 1
    GROUP BY pp.inscripcion_id
),
-- 3) Total general del plan de pagos por alumno
cte_saldo_total_plan AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_total,
        SUM(pp.monto - pp.saldo) AS cancelado_total,
        SUM(pp.saldo) AS saldo_total
    FROM productionacademicoesamdb.plan_pagos pp
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
    -- Columnas financieras completas para Cuota Inicial (Concepto 133)
    IFNULL(ci.monto_cuota_inicial, 0) AS MONTO_CUOTA_INICIAL,
    IFNULL(ci.cancelado_cuota_inicial, 0) AS CANCELADO_CUOTA_INICIAL,
    IFNULL(ci.saldo_cuota_inicial, 0) AS SALDO_CUOTA_INICIAL,
    -- Columnas financieras completas para Colegiatura C1 (Concepto 2)
    IFNULL(cc1.monto_colegiatura_c1, 0) AS MONTO_COLEGIATURA_INICIAL,
    IFNULL(cc1.cancelado_colegiatura_c1, 0) AS CANCELADO_COLEGIATURA_INICIAL,
    IFNULL(cc1.saldo_colegiatura_c1, 0) AS SALDO_COLEGIATURA_INICIAL,
    -- Columnas financieras completas para el Total del Plan
    IFNULL(stp.monto_total, 0) AS MONTO_TOTAL,
    IFNULL(stp.cancelado_total, 0) AS CANCELADO_TOTAL,
    IFNULL(stp.saldo_total, 0) AS SALDO_TOTAL,
    -- Fecha de pago que rige la productividad
    CASE
        WHEN IFNULL(ci.saldo_cuota_inicial, 1) = 0 AND IFNULL(cc1.saldo_colegiatura_c1, 1) = 0 THEN
            CASE 
                WHEN ci.fecha_primer_pago_inicial <= cc1.fecha_primer_pago_colegiatura THEN ci.fecha_primer_pago_inicial 
                ELSE cc1.fecha_primer_pago_colegiatura 
            END
        WHEN IFNULL(ci.saldo_cuota_inicial, 1) = 0 THEN ci.fecha_primer_pago_inicial
        WHEN IFNULL(cc1.saldo_colegiatura_c1, 1) = 0 THEN cc1.fecha_primer_pago_colegiatura
        ELSE COALESCE(ci.fecha_primer_pago_inicial, cc1.fecha_primer_pago_colegiatura)
    END AS FECHA_PAGO_PRODUCTIVIDAD,
    -- Condición de productividad
    IF(IFNULL(ci.saldo_cuota_inicial, 1) = 0 OR IFNULL(cc1.saldo_colegiatura_c1, 1) = 0, 'INSCRITO', 'NO INSCRITO') AS CONDICION_PRODUCTIVIDAD,
    CASE
        WHEN i.estado_ins = 0 THEN 'PRE-INSCRITO'
        WHEN i.estado_ins = 1 THEN 'INSCRITO'
        WHEN i.estado_ins = 2 THEN 'RETIRADO'
        WHEN i.estado_ins = 3 THEN 'CAMBIADO'
        WHEN i.estado_ins = 4 THEN 'CONGELADO'
        WHEN i.estado_ins = 5 THEN 'PAGADO'
        ELSE 'NO IDENTIFICADO'
    END AS ESTADO_INSCRIPCION,
    IFNULL(i2.abreviatura, 'Sin Convenio') AS CONVENIO,
    CASE MONTH(
        CASE
            WHEN IFNULL(ci.saldo_cuota_inicial, 1) = 0 AND IFNULL(cc1.saldo_colegiatura_c1, 1) = 0 THEN
                CASE WHEN ci.fecha_primer_pago_inicial <= cc1.fecha_primer_pago_colegiatura THEN ci.fecha_primer_pago_inicial ELSE cc1.fecha_primer_pago_colegiatura END
            WHEN IFNULL(ci.saldo_cuota_inicial, 1) = 0 THEN ci.fecha_primer_pago_inicial
            WHEN IFNULL(cc1.saldo_colegiatura_c1, 1) = 0 THEN cc1.fecha_primer_pago_colegiatura
            ELSE COALESCE(ci.fecha_primer_pago_inicial, cc1.fecha_primer_pago_colegiatura)
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
-- Joins con las CTEs
LEFT JOIN  cte_cuota_inicial ci ON ci.inscripcion_id = i.id
LEFT JOIN  cte_colegiatura_c1 cc1 ON cc1.inscripcion_id = i.id
LEFT JOIN  cte_saldo_total_plan stp ON stp.inscripcion_id = i.id
-- Filtros
WHERE s.id IN (24,27,28,29,30,31,32,33,42,53,107)
  AND i2.id = 49
  AND (
        CASE
            WHEN IFNULL(ci.saldo_cuota_inicial, 1) = 0 AND IFNULL(cc1.saldo_colegiatura_c1, 1) = 0 THEN
                CASE WHEN ci.fecha_primer_pago_inicial <= cc1.fecha_primer_pago_colegiatura THEN ci.fecha_primer_pago_inicial ELSE cc1.fecha_primer_pago_colegiatura END
            WHEN IFNULL(ci.saldo_cuota_inicial, 1) = 0 THEN ci.fecha_primer_pago_inicial
            WHEN IFNULL(cc1.saldo_colegiatura_c1, 1) = 0 THEN cc1.fecha_primer_pago_colegiatura
            ELSE COALESCE(ci.fecha_primer_pago_inicial, cc1.fecha_primer_pago_colegiatura)
        END
      ) BETWEEN '2026-01-01 00:00:00' AND NOW()
ORDER BY i.id;