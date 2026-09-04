WITH
-- 1) Mensualidad Cuota 1 — se usa para determinar inscripción en Carreras
cte_mensualidad_c1 AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_mensualidad_c1,
        SUM(pp.saldo) AS saldo_mensualidad_c1,
        MAX(dpi.fecha_registro_pago) AS fecha_pago_mensualidad_c1,
        MAX(pi.nro_recibo) AS nro_recibo_mensualidad_c1
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN productionacademicoesamdb.detalle_pagos_inscripcion dpi
           ON dpi.cuota_id = pp.id AND dpi.estado = 1
    LEFT JOIN productionacademicoesamdb.pagos_inscripcion pi
           ON pi.id = dpi.pagos_inscripcion_id AND pi.estado = 1
    WHERE pp.concepto_pago_id = 8 AND pp.nro_cuota = 1
    GROUP BY pp.inscripcion_id
),
-- 2) Saldo total del plan — se usa para determinar inscripción en Cursos
cte_saldo_total AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_total_plan,
        SUM(pp.saldo) AS saldo_total_plan,
        MAX(dpi.fecha_registro_pago) AS fecha_pago_total_plan
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN productionacademicoesamdb.detalle_pagos_inscripcion dpi
           ON dpi.cuota_id = pp.id AND dpi.estado = 1
    LEFT JOIN productionacademicoesamdb.pagos_inscripcion pi
           ON pi.id = dpi.pagos_inscripcion_id AND pi.estado = 1
    -- Filtramos solo los conceptos de pago de CCA relevantes (Mensualidades y Formación Continua)
    WHERE pp.concepto_pago_id IN (8, 17)
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
    -- Clasificamos de forma binaria si es Curso o Carrera usando los IDs de categoría
    CASE 
        WHEN c.id IN (8, 9, 10) THEN 1 
        ELSE 0 
    END AS ES_CURSO,
    IFNULL(mc1.monto_mensualidad_c1, 0) AS MONTO_MENSUALIDAD_CUOTA1,
    IFNULL(mc1.saldo_mensualidad_c1, 0) AS SALDO_MENSUALIDAD_CUOTA1,
    IFNULL(st.monto_total_plan, 0) AS MONTO_TOTAL_PLAN,
    IFNULL(st.saldo_total_plan, 0) AS SALDO_TOTAL_PLAN,
    -- Fecha de pago que rige la productividad
    CASE
        WHEN c.id IN (8, 9, 10) THEN st.fecha_pago_total_plan
        ELSE mc1.fecha_pago_mensualidad_c1
    END AS FECHA_PAGO_PRODUCTIVIDAD,
    -- Condición para considerar al alumno inscrito (Saldo = 0 según tipo de programa)
    CASE
        WHEN c.id IN (8, 9, 10) THEN 
            IF(IFNULL(st.saldo_total_plan, 1) = 0, 'INSCRITO', 'NO INSCRITO')
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
    IFNULL(i2.abreviatura, 'Sin Convenio') AS CONVENIO,
    -- Determinación del mes en base a la fecha de productividad
    CASE MONTH(
        CASE
            WHEN c.id IN (8, 9, 10) THEN st.fecha_pago_total_plan
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
LEFT JOIN  productionadminesamdb.instituciones i2 ON i2.id = p.iduniversidad
-- Se enlazan los CTEs
LEFT JOIN cte_mensualidad_c1 mc1 ON mc1.inscripcion_id = i.id
LEFT JOIN cte_saldo_total st ON st.inscripcion_id = i.id
-- Filtros de sede para CCA y rango de fechas de productividad
WHERE s.id IN (9,10,48,79)
  AND (
        CASE
            WHEN c.id IN (8, 9, 10) THEN st.fecha_pago_total_plan
            ELSE mc1.fecha_pago_mensualidad_c1
        END
      ) BETWEEN '2026-01-01 00:00:00' AND NOW()
ORDER BY i.id;