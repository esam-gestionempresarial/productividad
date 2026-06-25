SELECT
    un.nombre AS UNIDAD,
    s.nombre AS SEDE,
    CONCAT_WS(' ', p3.nombres, p3.pri_apellido, p3.seg_apellido) AS ASESOR,
    p3.num_doc AS CI_ASESOR,
    CONCAT_WS(' ', p4.nombres, p4.pri_apellido, p4.seg_apellido) AS ALUMNO,
    p4.num_doc AS CI_ALUMNO,
    c.nombre AS TIPO,
    i.id AS ID_INSCRIPCION,
    p.codigo AS COD_CONTABLE,
    p.nombre_compuesto AS PROGRAMA,
    p.id AS ID_PROGRAMA,
    /* ── Tipo de Plan de Pago ── */
    IF(UPPER(pcp.nombre) LIKE '%CONTADO%', 'Contado', 'Crédito') AS TIPO_PLAN_PAGO,
    DATE(i.fecha_registro) AS FECHA_REGISTRO,
    finanzas.fecha_primer_pago AS FECHA_PRIMER_PAGO,
    /* ── Estado Esam Real (Parámetros de inscripción)  ── */
    CASE
        WHEN ei.id IN (0,1,2,3,4,5) AND finanzas.total_formativo = 0  THEN 'Prospecto'
        WHEN ei.nombre = 'Retirado' AND finanzas.total_formativo < (CASE WHEN c.nombre = 'Diplomado' THEN 600 ELSE 800 END) THEN 'Retirado Preinscrito'
        WHEN ei.nombre = 'Retirado' AND finanzas.total_formativo >= (CASE WHEN c.nombre = 'Diplomado' THEN 600 ELSE 800 END) THEN 'Retirado Inscrito'
        WHEN ei.nombre = 'Cambiado' AND finanzas.total_formativo < (CASE WHEN c.nombre = 'Diplomado' THEN 600 ELSE 800 END) THEN 'Cambiado Preinscrito'
        WHEN ei.nombre = 'Cambiado' AND finanzas.total_formativo >= (CASE WHEN c.nombre = 'Diplomado' THEN 600 ELSE 800 END) THEN 'Cambiado Inscrito'
        WHEN ei.id IN (0,1,4,5) AND finanzas.total_formativo <  (CASE WHEN c.nombre = 'Diplomado' THEN 600 ELSE 800 END) THEN 'Preinscrito'
        WHEN ei.id IN (0,1) AND finanzas.total_formativo >= (CASE WHEN c.nombre = 'Diplomado' THEN 600 ELSE 800 END) THEN 'Inscrito'
        ELSE IFNULL(ei.nombre, 'sin definir')
    END AS ESTADO,
    /* ── Desglose de Conceptos Pagados ── */
    IFNULL(finanzas.pago_matricula, 0) AS PAGO_MATRICULA,
    IFNULL(finanzas.pago_colegiatura, 0) AS PAGO_COLEGIATURA,
    /* ── Información Financiera Consolidada ── */
    IFNULL(finanzas.monto_total_plan, 0) AS MONTO_TOTAL,
    IFNULL(finanzas.monto_cancelado, 0) AS MONTO_CANCELADO,
    IFNULL(finanzas.saldo, 0) AS SALDO,
    IFNULL(i2.abreviatura, 'Sin Convenio') AS CONVENIO
FROM inscripciones i
INNER JOIN programas p ON i.idprograma = p.id
INNER JOIN postgrados p2 ON p.idpostgrado = p2.id
INNER JOIN categorias c ON p2.idcategoria = c.id
LEFT JOIN estados_inscripcion ei ON ei.id = i.estado_ins
LEFT JOIN plan_cobros_programa pcp ON i.plan_cobro_programa_id = pcp.id
LEFT JOIN productionadminesamdb.personas p3 ON i.idasesor = p3.id
INNER JOIN productionadminesamdb.personas p4 ON i.idestudiante = p4.id
INNER JOIN productionadminesamdb.sedes s ON p.idsede = s.id
LEFT JOIN productionadminesamdb.unidad_negocio un ON s.unidad_negocio = un.id
LEFT JOIN productionadminesamdb.instituciones i2 ON p.iduniversidad = i2.id
/* ════════════════════════════════════════════════════
   SUBQUERY FINANCIERA (Optimizada con Conceptos)
   ════════════════════════════════════════════════════ */
LEFT JOIN (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_total_plan,
        SUM(IFNULL(pagos.monto_pagado, 0)) AS monto_cancelado,
        (SUM(pp.monto) - SUM(IFNULL(pagos.monto_pagado, 0))) AS saldo,
        DATE(MIN(CASE WHEN pp.nro_cuota = 1 THEN pagos.fecha_pago_efectivo END)) AS fecha_primer_pago,
        SUM(CASE WHEN pp.concepto_pago_id = 1 THEN IFNULL(pagos.monto_pagado, 0) ELSE 0 END) AS pago_matricula,
        SUM(CASE WHEN pp.concepto_pago_id = 2 THEN IFNULL(pagos.monto_pagado, 0) ELSE 0 END) AS pago_colegiatura,
        SUM(CASE WHEN pp.concepto_pago_id IN (1, 2) THEN IFNULL(pagos.monto_pagado, 0) ELSE 0 END) AS total_formativo
    FROM plan_pagos pp
    LEFT JOIN (
        SELECT
            cuota_id,
            SUM(monto) AS monto_pagado,
            MIN(fecha_registro_pago) AS fecha_pago_efectivo
        FROM detalle_pagos_inscripcion
        WHERE estado = 1
        GROUP BY cuota_id
    ) pagos ON pagos.cuota_id = pp.id
    GROUP BY pp.inscripcion_id
) finanzas ON finanzas.inscripcion_id = i.id
WHERE s.id IN (1,2,3,4,5,6,7,8,14,15,16,18,20,22,23,25,26,37,50,51,52,80,125,127,128,129)
  AND finanzas.monto_total_plan > 1
  AND i.fecha_registro BETWEEN '2026-01-01 00:00:00' AND '2026-05-31 23:59:59'
ORDER BY i.fecha_registro ASC;