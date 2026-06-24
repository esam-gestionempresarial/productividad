SELECT
    un.nombre AS UNIDAD,
    s.nombre AS SEDE,
    CONCAT_WS(' ', p2.nombres, p2.pri_apellido, p2.seg_apellido) AS ASESOR,
    p2.num_doc AS `CI ASESOR`,
    i.id AS ID_INSCRIPCION,
    DATE(i.fecha_registro) AS FECHA_REGISTRO,
    CONCAT_WS(' ', p3.nombres, p3.pri_apellido, p3.seg_apellido) AS ALUMNO,
    p3.num_doc AS CI_ALUMNO,
    c.nombre AS TIPO,
    p.codigo AS COD_CONTABLE,
    p.nombre_compuesto AS PROGRAMA,
    /* Identifica si el plan es Contado o Crédito */
    IF(pcp.nombre LIKE '%CONTADO%', 'Contado', 'Crédito') AS TIPO_PLAN_PAGO,
    /* DESGLOSE DE CONCEPTOS REALES PAGADOS (Control dpi.estado = 1) */
    kardex.pago_matricula AS MATRICULA,
    /* La suma de todas las cuotas pagadas */
    kardex.total_cuotas AS TOTAL_CUOTAS,
    /* Fecha del primer pago cronológico realizado */
    kardex.fecha_primer_pago AS FECHA_PAGO_1RA_CUOTA,
    /* Lógica de Estado_UPI según la fase formativa */
    CASE 
        WHEN kardex.total_cuotas= 0 THEN 'Prospecto'
        WHEN c.nombre = 'Licenciatura'          THEN IF(kardex.total_cuotas BETWEEN 1 AND 109, 'Pre inscrito', 'Inscrito')
        WHEN c.nombre = 'Técnico Universitario' THEN IF(kardex.total_cuotas BETWEEN 1 AND 99,  'Pre inscrito', 'Inscrito')
        WHEN c.nombre = 'Diplomado'             THEN IF(kardex.total_cuotas BETWEEN 1 AND 89,  'Pre inscrito', 'Inscrito')
        WHEN c.nombre = 'Maestría'              THEN IF(kardex.total_cuotas BETWEEN 1 AND 149, 'Pre inscrito', 'Inscrito')
        ELSE 'Sin Estado'
    END AS ESTADO_UPI,
    /* ── INFORMACIÓN FINANCIERA GLOBAL ── */
    kardex.monto_total_plan AS MONTO_TOTAL_PLAN,
    kardex.monto_total_cancelado AS MONTO_CANCELADO,
    kardex.monto_total_saldo AS SALDO
FROM productionacademicoesamdb.inscripciones i 
INNER JOIN productionacademicoesamdb.programas p ON i.idprograma = p.id
INNER JOIN productionacademicoesamdb.postgrados p4 ON p.idpostgrado = p4.id
INNER JOIN productionacademicoesamdb.categorias c ON p4.idcategoria = c.id
INNER JOIN productionacademicoesamdb.plan_cobros_programa pcp ON i.plan_cobro_programa_id = pcp.id
INNER JOIN productionadminesamdb.sedes s ON p.idsede = s.id
INNER JOIN productionadminesamdb.personas p2 ON i.idasesor = p2.id 
INNER JOIN productionadminesamdb.personas p3 ON i.idestudiante = p3.id
INNER JOIN productionadminesamdb.unidad_negocio un ON s.unidad_negocio = un.id 
/* ════════════════════════════════════════════════════
   SUBQUERY KARDEX: Agrupación financiera por inscrito
   ════════════════════════════════════════════════════ */
INNER JOIN (
    SELECT 
        pp.inscripcion_id,
        -- Totales económicos globales de la cuenta del alumno
        SUM(pp.monto) AS monto_total_plan,
        SUM(IFNULL(dpi.monto, 0)) AS monto_total_cancelado,
        SUM(pp.monto - IFNULL(dpi.monto, 0)) AS monto_total_saldo,
        -- Apertura analítica de montos reales pagados por concepto principal
        SUM(CASE WHEN pp.concepto_pago_id = 1 THEN IFNULL(dpi.monto, 0) ELSE 0 END) AS pago_matricula,
        -- Lógica para mostrar la suma de TODAS las cuotas pagadas (Basado en nro_cuota > 0)
        SUM(CASE WHEN pp.nro_cuota > 0 THEN IFNULL(dpi.monto, 0) ELSE 0 END) AS total_cuotas,      
        -- Captura del primer pago histórico válido en el tiempo
        DATE(MIN(CASE WHEN dpi.estado = 1 THEN pi2.fecha_registro END)) AS fecha_primer_pago
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN productionacademicoesamdb.detalle_pagos_inscripcion dpi ON pp.id = dpi.cuota_id AND dpi.estado = 1
    LEFT JOIN productionacademicoesamdb.pagos_inscripcion pi2 ON pi2.id = dpi.pagos_inscripcion_id
    GROUP BY pp.inscripcion_id
) kardex ON kardex.inscripcion_id = i.id
WHERE s.id IN (82,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,102,103,104,105,106,108,109,115,116,117,118,119,120,121,122,123,124,126)
  AND i.fecha_registro BETWEEN '2026-01-01 00:00:00' AND '2026-05-31 23:59:59'
ORDER BY i.fecha_registro ASC;