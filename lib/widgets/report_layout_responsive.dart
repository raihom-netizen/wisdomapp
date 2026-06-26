import 'dart:math' as math;

/// Largura máxima do conteúdo central em Relatórios (PWA / tablet / desktop).
const double kReportContentMaxWidth = 1040;

/// Abaixo disso: “Por conta” em cards, gráficos compactos, e [ReportsScreen] resumo (3 KPIs) em coluna.
const double kReportGridBreakpointCompact = 520;

/// Tiles com duas colunas (texto | ações) viram coluna empilhada.
const double kReportTileStackBreakpoint = 420;

/// Período financeiro (subtotais) empilha rótulo e valor.
const double kReportSubtotalStackBreakpoint = 400;

double reportContentWidth(double available) =>
    math.min(kReportContentMaxWidth, available);

bool reportIsCompactWidth(double width) => width < kReportGridBreakpointCompact;

bool reportStackTiles(double width) => width < kReportTileStackBreakpoint;
