WITH
-- 1) Matrícula (concepto 1) — solo aplica en modalidad Crédito
cte_matricula AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_matricula,
        SUM(pp.saldo) AS saldo_matricula,
        MAX(dpi.fecha_registro_pago) AS fecha_primer_pago_matricula,
        MAX(pi.nro_recibo) AS nro_recibo_matricula
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN productionacademicoesamdb.detalle_pagos_inscripcion dpi
           ON dpi.cuota_id = pp.id AND dpi.estado = 1
    LEFT JOIN productionacademicoesamdb.pagos_inscripcion pi
           ON pi.id = dpi.pagos_inscripcion_id AND pi.estado = 1
    WHERE pp.concepto_pago_id = 1
    GROUP BY pp.inscripcion_id
),
-- 2) Colegiatura, cuota 1 — aplica a ambas modalidades (posgrados)
cte_colegiatura_c1 AS (
    SELECT
        pp.inscripcion_id,
        pp.monto AS monto_colegiatura_c1,
        pp.saldo AS saldo_colegiatura_c1,
        MAX(dpi.fecha_registro_pago) AS fecha_primer_pago_colegiatura,
        MAX(pi.nro_recibo) AS nro_recibo_colegiatura
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN productionacademicoesamdb.detalle_pagos_inscripcion dpi
           ON dpi.cuota_id = pp.id AND dpi.estado = 1
    LEFT JOIN productionacademicoesamdb.pagos_inscripcion pi
           ON pi.id = dpi.pagos_inscripcion_id AND pi.estado = 1
    WHERE pp.concepto_pago_id = 2 AND pp.nro_cuota = 1
    GROUP BY pp.inscripcion_id, pp.monto, pp.saldo
),
-- 3) Saldo total del plan completo — se usa SOLO para cursos de capacitación
cte_saldo_total AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_total_plan,
        SUM(pp.saldo) AS saldo_total_plan,
        MAX(dpi.fecha_registro_pago) AS fecha_primer_pago_plan
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN productionacademicoesamdb.detalle_pagos_inscripcion dpi
           ON dpi.cuota_id = pp.id AND dpi.estado = 1
    LEFT JOIN productionacademicoesamdb.pagos_inscripcion pi
           ON pi.id = dpi.pagos_inscripcion_id AND pi.estado = 1
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
    CASE WHEN c.nombre IN ('Esam Cursos', 'Curso Modular') THEN 1 ELSE 0 END AS ES_CURSO,
    IFNULL(mat.monto_matricula, 0) AS MONTO_MATRICULA,
    IFNULL(mat.saldo_matricula, 0) AS SALDO_MATRICULA,
    IFNULL(cc1.monto_colegiatura_c1, 0) AS MONTO_COLEGIATURA_CUOTA1,
    IFNULL(cc1.saldo_colegiatura_c1, 0) AS SALDO_COLEGIATURA_CUOTA1,
    IFNULL(st.monto_total_plan, 0) AS MONTO_TOTAL_PLAN,
    IFNULL(st.saldo_total_plan, 0) AS SALDO_TOTAL_PLAN,
    -- Fecha de pago que rige la productividad (varía según tipo de producto/plan)
    CASE
        WHEN c.nombre IN ('Esam Cursos', 'Curso Modular') THEN st.fecha_primer_pago_plan
        WHEN UPPER(pcp.nombre) LIKE '%CONTADO%' THEN cc1.fecha_primer_pago_colegiatura
        ELSE COALESCE(cc1.fecha_primer_pago_colegiatura, mat.fecha_primer_pago_matricula)
    END AS FECHA_PAGO_PRODUCTIVIDAD,
    CASE
        WHEN c.nombre IN ('Esam Cursos', 'Curso Modular')
            THEN IF(IFNULL(st.saldo_total_plan, 1) = 0, 'INSCRITO', 'NO INSCRITO')
        WHEN UPPER(pcp.nombre) LIKE '%CONTADO%'
            THEN IF(IFNULL(cc1.saldo_colegiatura_c1, 1) = 0, 'INSCRITO', 'NO INSCRITO')
        ELSE
            IF(IFNULL(mat.saldo_matricula, 1) = 0 AND IFNULL(cc1.saldo_colegiatura_c1, 1) = 0,
               'INSCRITO', 'NO INSCRITO')
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
    CASE MONTH(
    CASE
        WHEN c.nombre IN ('Esam Cursos', 'Curso Modular') THEN st.fecha_primer_pago_plan
        WHEN UPPER(pcp.nombre) LIKE '%CONTADO%' THEN cc1.fecha_primer_pago_colegiatura
        ELSE COALESCE(cc1.fecha_primer_pago_colegiatura, mat.fecha_primer_pago_matricula)
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
END AS MES,
i.created_at AS fecha_creacion_inscripcion
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
LEFT JOIN  cte_matricula mat ON mat.inscripcion_id = i.id
LEFT JOIN  cte_colegiatura_c1 cc1 ON cc1.inscripcion_id = i.id
LEFT JOIN  cte_saldo_total st ON st.inscripcion_id = i.id
WHERE s.id IN (1,2,3,4,5,6,7,8,14,15,16,18,20,22,23,25,26,37,50,51,52,80,125,127,128,129,132)
  AND i2.id = 9
  AND (
        CASE
            WHEN c.nombre IN ('Esam Cursos', 'Curso Modular') THEN st.fecha_primer_pago_plan
            WHEN UPPER(pcp.nombre) LIKE '%CONTADO%' THEN cc1.fecha_primer_pago_colegiatura
            ELSE COALESCE(cc1.fecha_primer_pago_colegiatura, mat.fecha_primer_pago_matricula)
        END
      ) BETWEEN '2026-01-01 00:00:00' AND NOW()
ORDER BY cc1.fecha_primer_pago_colegiatura;