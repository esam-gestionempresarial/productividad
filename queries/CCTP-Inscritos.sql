WITH
-- CTE 0: Subconsulta pre-agrupada para obtener pagos sin duplicar filas en plan_pagos (Evita Fan-out)
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
-- 1) Mensualidad Cuota 1 — determina inscripción en Programas (Concepto 8)
cte_mensualidad_c1 AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_mensualidad_c1,
        SUM(pp.monto - pp.saldo) AS cancelado_mensualidad_c1,
        SUM(pp.saldo) AS saldo_mensualidad_c1,
        MAX(pinfo.fecha_pago) AS fecha_pago_mensualidad_c1,
        MAX(pinfo.nro_recibo) AS nro_recibo_mensualidad_c1
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN cte_pagos_info pinfo ON pinfo.cuota_id = pp.id
    WHERE pp.concepto_pago_id = 8 AND pp.nro_cuota = 1
    GROUP BY pp.inscripcion_id
),
-- 2) Curso Cuota 1 — determina inscripción en Cursos (Concepto 18)
cte_curso_c1 AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_curso_c1,
        SUM(pp.monto - pp.saldo) AS cancelado_curso_c1,
        SUM(pp.saldo) AS saldo_curso_c1,
        MAX(pinfo.fecha_pago) AS fecha_pago_curso_c1,
        MAX(pinfo.nro_recibo) AS nro_recibo_curso_c1
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN cte_pagos_info pinfo ON pinfo.cuota_id = pp.id
    WHERE pp.concepto_pago_id = 18 AND pp.nro_cuota = 1
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
    -- Clasificación binaria (1 = Curso, 0 = Programa)
    CASE 
        WHEN UPPER(p.nombre_compuesto) LIKE '%CURSO%' THEN 1 
        ELSE 0 
    END AS ES_CURSO,
    -- Información financiera para Mensualidad Cuota 1 (Programas)
    IFNULL(mc1.monto_mensualidad_c1, 0) AS MONTO_MENSUALIDAD_CUOTA1,
    IFNULL(mc1.cancelado_mensualidad_c1, 0) AS CANCELADO_MENSUALIDAD_CUOTA1,
    IFNULL(mc1.saldo_mensualidad_c1, 0) AS SALDO_MENSUALIDAD_CUOTA1,
    -- Información financiera para Curso Cuota 1 (Cursos)
    IFNULL(cc1.monto_curso_c1, 0) AS MONTO_CURSO_CUOTA1,
    IFNULL(cc1.cancelado_curso_c1, 0) AS CANCELADO_CURSO_CUOTA1,
    IFNULL(cc1.saldo_curso_c1, 0) AS SALDO_CURSO_CUOTA1,
    -- Fecha de pago que rige la productividad
    CASE
        WHEN UPPER(p.nombre_compuesto) LIKE '%CURSO%' THEN cc1.fecha_pago_curso_c1
        ELSE mc1.fecha_pago_mensualidad_c1
    END AS FECHA_PAGO_PRODUCTIVIDAD,
    -- Condición para considerar al alumno inscrito (Saldo = 0 en Cuota 1)
    CASE
        WHEN UPPER(p.nombre_compuesto) LIKE '%CURSO%' THEN 
            IF(IFNULL(cc1.saldo_curso_c1, 1) = 0, 'INSCRITO', 'NO INSCRITO')
        ELSE 
            IF(IFNULL(mc1.saldo_mensualidad_c1, 1) = 0, 'INSCRITO', 'NO INSCRITO')
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
    -- Determinación del mes
    CASE MONTH(
        CASE
            WHEN UPPER(p.nombre_compuesto) LIKE '%CURSO%' THEN cc1.fecha_pago_curso_c1
            ELSE mc1.fecha_pago_mensualidad_c1
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
INNER JOIN productionadminesamdb.personas p4 ON p4.id = i.idestudiante
LEFT JOIN  productionadminesamdb.personas p3 ON p3.id = i.idasesor
INNER JOIN productionadminesamdb.sedes s ON s.id = p.idsede
LEFT JOIN  productionadminesamdb.unidad_negocio un ON un.id = s.unidad_negocio
-- Enlace con CTEs
LEFT JOIN cte_mensualidad_c1 mc1 ON mc1.inscripcion_id = i.id
LEFT JOIN cte_curso_c1 cc1 ON cc1.inscripcion_id = i.id
-- Filtros para CCTP (Sede 39) y rango de fechas
WHERE s.id = 39
  AND (
        CASE
            WHEN UPPER(p.nombre_compuesto) LIKE '%CURSO%' THEN cc1.fecha_pago_curso_c1
            ELSE mc1.fecha_pago_mensualidad_c1
        END
      ) BETWEEN '2026-01-01 00:00:00' AND NOW()
ORDER BY i.id;