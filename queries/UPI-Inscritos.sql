WITH
-- 1) Matrícula (concepto 1)
cte_matricula AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_matricula,
        SUM(pp.saldo) AS saldo_matricula,
        MAX(dpi.fecha_registro_pago) AS fecha_primer_pago_matricula
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN productionacademicoesamdb.detalle_pagos_inscripcion dpi ON dpi.cuota_id = pp.id AND dpi.estado = 1
    LEFT JOIN productionacademicoesamdb.pagos_inscripcion pi ON pi.id = dpi.pagos_inscripcion_id AND pi.estado = 1
    WHERE pp.concepto_pago_id = 1
    GROUP BY pp.inscripcion_id
),
-- 2) Colegiatura 1 (concepto 2)
cte_colegiatura_c1 AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_colegiatura1,
        SUM(pp.saldo) AS saldo_colegiatura1,
        MAX(dpi.fecha_registro_pago) AS fecha_primer_pago_colegiatura
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN productionacademicoesamdb.detalle_pagos_inscripcion dpi ON dpi.cuota_id = pp.id AND dpi.estado = 1
    LEFT JOIN productionacademicoesamdb.pagos_inscripcion pi ON pi.id = dpi.pagos_inscripcion_id AND pi.estado = 1
    WHERE pp.concepto_pago_id = 2 AND pp.nro_cuota = 1
    GROUP BY pp.inscripcion_id
),
-- 3) Cuota 1 (concepto 312)
cte_cuota_c1 AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_cuota1,
        SUM(pp.saldo) AS saldo_cuota1,
        MAX(dpi.fecha_registro_pago) AS fecha_primer_pago_cuota
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN productionacademicoesamdb.detalle_pagos_inscripcion dpi ON dpi.cuota_id = pp.id AND dpi.estado = 1
    LEFT JOIN productionacademicoesamdb.pagos_inscripcion pi ON pi.id = dpi.pagos_inscripcion_id AND pi.estado = 1
    WHERE pp.concepto_pago_id = 312 AND pp.nro_cuota = 1
    GROUP BY pp.inscripcion_id
),
-- 4) Saldo total del plan completo
cte_saldo_total AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_total_plan,
        SUM(pp.saldo) AS saldo_total_plan
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
    -- Columnas de montos separadas
    IFNULL(mat.monto_matricula, 0) AS MONTO_MATRICULA,
    IFNULL(mat.saldo_matricula, 0) AS SALDO_MATRICULA,
    IFNULL(cc1.monto_colegiatura1, 0) AS MONTO_COLEGIATURA1,
    IFNULL(cc1.saldo_colegiatura1, 0) AS SALDO_COLEGIATURA1,
    IFNULL(cu1.monto_cuota1, 0) AS MONTO_CUOTA1,
    IFNULL(cu1.saldo_cuota1, 0) AS SALDO_CUOTA1,
    IFNULL(st.monto_total_plan, 0) AS MONTO_TOTAL_PLAN,
    IFNULL(st.saldo_total_plan, 0) AS SALDO_TOTAL_PLAN,
    -- Toma la fecha más reciente de pago entre matrícula y (Colegiatura 1 o Cuota 1)
    CASE 
        WHEN mat.fecha_primer_pago_matricula IS NOT NULL AND COALESCE(cc1.fecha_primer_pago_colegiatura, cu1.fecha_primer_pago_cuota) IS NOT NULL 
            THEN GREATEST(mat.fecha_primer_pago_matricula, COALESCE(cc1.fecha_primer_pago_colegiatura, cu1.fecha_primer_pago_cuota))
        ELSE COALESCE(cc1.fecha_primer_pago_colegiatura, cu1.fecha_primer_pago_cuota, mat.fecha_primer_pago_matricula)
    END AS FECHA_PAGO_PRODUCTIVIDAD,
    -- Se evalúa que matrícula sea 0 (o no exista) y que (Colegiatura 1 o Cuota 1) esté en 0
    IF(
        IFNULL(mat.saldo_matricula, 0) = 0 
        AND COALESCE(cc1.saldo_colegiatura1, cu1.saldo_cuota1, 1) = 0, 
        'INSCRITO', 'NO INSCRITO'
    ) AS CONDICION_PRODUCTIVIDAD,
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
            WHEN mat.fecha_primer_pago_matricula IS NOT NULL AND COALESCE(cc1.fecha_primer_pago_colegiatura, cu1.fecha_primer_pago_cuota) IS NOT NULL 
                THEN GREATEST(mat.fecha_primer_pago_matricula, COALESCE(cc1.fecha_primer_pago_colegiatura, cu1.fecha_primer_pago_cuota))
            ELSE COALESCE(cc1.fecha_primer_pago_colegiatura, cu1.fecha_primer_pago_cuota, mat.fecha_primer_pago_matricula)
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
LEFT JOIN  cte_matricula mat ON mat.inscripcion_id = i.id
LEFT JOIN  cte_colegiatura_c1 cc1 ON cc1.inscripcion_id = i.id
LEFT JOIN  cte_cuota_c1 cu1 ON cu1.inscripcion_id = i.id
LEFT JOIN  cte_saldo_total st ON st.inscripcion_id = i.id
WHERE s.id IN (24,27,28,29,30,31,32,33,42,53,107, /* Sedes DBS */
				1,2,3,4,5,6,7,8,14,15,16,18,20,22,23,25,26,37,50,51,52,80,125,127,128,129,132,134, /* Sedes Esam */
				82,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,102,103,104,105,106,108,109,115,116,117,118,119,120,121,122,123,124,126)  /* Sedes UPI */
  AND i2.id IN (301,307)
  AND (
        CASE 
            WHEN mat.fecha_primer_pago_matricula IS NOT NULL AND COALESCE(cc1.fecha_primer_pago_colegiatura, cu1.fecha_primer_pago_cuota) IS NOT NULL 
                THEN GREATEST(mat.fecha_primer_pago_matricula, COALESCE(cc1.fecha_primer_pago_colegiatura, cu1.fecha_primer_pago_cuota))
            ELSE COALESCE(cc1.fecha_primer_pago_colegiatura, cu1.fecha_primer_pago_cuota, mat.fecha_primer_pago_matricula)
        END
      ) BETWEEN '2026-01-01 00:00:00' AND NOW()
ORDER BY i.id;