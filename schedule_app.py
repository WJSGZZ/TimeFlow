"""
课程表桌面软件
pip install PyQt6
python schedule_app.py
"""
import sys, json, os
from datetime import datetime, timedelta
from PyQt6.QtWidgets import *
from PyQt6.QtCore import *
from PyQt6.QtGui import *

# ═══════════════════════════════════════════════
#  配色（Claude / Anthropic 风格）
# ═══════════════════════════════════════════════
C = {
    "bg":        QColor(245, 240, 232),
    "surface":   QColor(251, 248, 243),
    "header":    QColor(237, 232, 222),
    "border":    QColor(210, 202, 192),
    "text":      QColor(28, 25, 23),
    "muted":     QColor(118, 111, 105),
    "faint":     QColor(170, 163, 157),
    "accent":    QColor(207, 99, 71),
    "today_col": QColor(207, 99, 71, 14),
    "today_hdr": QColor(207, 99, 71, 26),
}

CARD_COLORS = [
    (QColor(207, 99,  71),  QColor(253, 238, 233)),
    (QColor(70,  122, 140), QColor(232, 242, 246)),
    (QColor(88,  120, 80),  QColor(234, 242, 232)),
    (QColor(118, 88,  134), QColor(239, 234, 244)),
    (QColor(134, 100, 60),  QColor(244, 237, 226)),
    (QColor(58,  122, 122), QColor(229, 242, 242)),
]

DAYS = ['周一','周二','周三','周四','周五','周六','周日']
SUMMER_MODE = False   # 全局夏令时开关

def _app_dir():
    """数据目录：打包后用 AppData/Roaming/TimeFlow，开发时用脚本同目录"""
    if getattr(sys, 'frozen', False):
        base = os.path.join(os.environ.get('APPDATA', os.path.expanduser('~')), 'TimeFlow')
        os.makedirs(base, exist_ok=True)
        return base
    return os.path.dirname(os.path.abspath(__file__))

def _res_dir():
    """资源目录：logo.svg / periods.json 所在位置（打包后在 _MEIPASS）"""
    if getattr(sys, 'frozen', False):
        return sys._MEIPASS
    return os.path.dirname(os.path.abspath(__file__))

def load_periods():
    p = os.path.join(_res_dir(), 'periods.json')
    if os.path.exists(p):
        with open(p, encoding='utf-8') as f:
            data = json.load(f)
        return [(d['n'], d['start'], d['end'],
                 d.get('summer_start', d['start']),
                 d.get('summer_end',   d['end']))
                for d in data['periods']]
    return [(1,'08:00','08:45'),(2,'08:55','09:40'),(3,'09:50','10:35'),
            (4,'10:45','11:30'),(5,'11:40','12:25'),(6,'13:30','14:15'),
            (7,'14:25','15:10'),(8,'15:20','16:05'),(9,'16:15','17:00'),
            (10,'18:30','19:15'),(11,'19:25','20:10')]

PERIODS = load_periods()

# ═══════════════════════════════════════════════
#  工具
# ═══════════════════════════════════════════════
def semester_start():
    now = datetime.now()
    d = datetime(now.year, 3 if now.month < 7 else 9, 1)
    while d.weekday() != 0:
        d += timedelta(days=1)
    return d

def current_week():
    return max(1, min(20, (datetime.now() - semester_start()).days // 7 + 1))

def week_dates(week):
    base = semester_start() + timedelta(weeks=week-1)
    return [base + timedelta(days=i) for i in range(7)]

def load_json():
    p = os.path.join(_app_dir(), 'schedule.json')
    if not os.path.exists(p): return []
    with open(p, encoding='utf-8') as f:
        return json.load(f)

def rgb(color): return f"rgb({color.red()},{color.green()},{color.blue()})" 

# ═══════════════════════════════════════════════
#  课程详情弹窗
# ═══════════════════════════════════════════════
class Popup(QWidget):
    def __init__(self, course, fg, bg):
        super().__init__(None,
            Qt.WindowType.Tool |
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.NoDropShadowWindowHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self._draw(course, fg, bg)
        self.adjustSize()

    def _draw(self, c, fg, bg):
        root = QVBoxLayout(self)
        root.setContentsMargins(10, 10, 10, 10)

        card = QFrame()
        card.setObjectName('card')
        card.setMinimumWidth(280)
        card.setMaximumWidth(420)
        card.setStyleSheet(f"""
            QFrame#card {{
                background: {rgb(C['surface'])};
                border: 1px solid {rgb(C['border'])};
                border-radius: 10px;
            }}
        """)
        eff = QGraphicsDropShadowEffect()
        eff.setBlurRadius(28)
        eff.setOffset(0, 6)
        eff.setColor(QColor(0, 0, 0, 45))
        card.setGraphicsEffect(eff)

        lay = QVBoxLayout(card)
        lay.setContentsMargins(20, 18, 20, 20)
        lay.setSpacing(0)

        name = QLabel(c.get('name', ''))
        name.setFont(QFont('Segoe UI', 12, QFont.Weight.DemiBold))
        name.setStyleSheet(f"color: {rgb(C['text'])};")
        name.setWordWrap(False)
        name.setSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Fixed)
        lay.addWidget(name)
        lay.addSpacing(10)

        wd = c.get('weekday', 1) or 1
        ps, pe = c.get('period_start',''), c.get('period_end','')
        tag = QLabel(f"{DAYS[wd-1]}   第 {ps} – {pe} 节")
        tag.setFont(QFont('Segoe UI', 9))
        tag.setFixedHeight(28)
        tag.setAlignment(Qt.AlignmentFlag.AlignCenter)
        tag.setStyleSheet(f"""
            color: {rgb(fg)};
            background: {rgb(bg)};
            border-radius: 5px;
            padding: 0 10px;
        """)
        lay.addWidget(tag)
        lay.addSpacing(16)

        sep = QFrame()
        sep.setFrameShape(QFrame.Shape.HLine)
        sep.setStyleSheet(f"background: {rgb(C['border'])}; border: none; max-height: 1px;")
        lay.addWidget(sep)
        lay.addSpacing(14)

        rows = [
            ('教师', c.get('teacher') or '—'),
            ('教室', ((c.get('location') or '') + ' ' + (c.get('room') or '')).strip() or '—'),
            ('周次', (c.get('weeks') or '') + (f"  共 {len(c.get('week_list',[]))} 周" if c.get('week_list') else '')),
        ]
        if c.get('classes'):
            rows.append(('班级', c['classes'].replace(';', '  ·  ')))

        for lbl, val in rows:
            row = QHBoxLayout()
            row.setSpacing(14)
            l = QLabel(lbl)
            l.setFont(QFont('Segoe UI', 8))
            l.setFixedWidth(30)
            l.setStyleSheet(f"color: {rgb(C['faint'])};")
            v = QLabel(val)
            v.setFont(QFont('Segoe UI', 9))
            v.setStyleSheet(f"color: {rgb(C['text'])};")
            v.setWordWrap(True)
            row.addWidget(l)
            row.addWidget(v, 1)
            lay.addLayout(row)
            lay.addSpacing(8)

        root.addWidget(card)

# ═══════════════════════════════════════════════
#  课程表网格
# ═══════════════════════════════════════════════
class Grid(QWidget):
    TIME_W  = 68
    HDR_H   = 50
    MIN_ROW = 56

    def __init__(self):
        super().__init__()
        self.courses = []
        self.week    = 1
        self.cmap    = {}
        self._cards  = []
        self._popup  = None
        self.scroll  = None
        QApplication.instance().installEventFilter(self)

    def eventFilter(self, obj, event):
        if (event.type() == QEvent.Type.MouseButtonPress
                and self._popup and self._popup.isVisible()):
            if not self._popup.geometry().contains(QCursor.pos()):
                self._popup.hide()
                self._popup = None
        return False

    def setup(self, courses, week, cmap):
        self.courses = courses
        self.week    = week
        self.cmap    = cmap
        self._rebuild()

    def _viewport_h(self):
        if self.scroll:
            return max(1, self.scroll.viewport().height())
        return max(1, self.height())

    DIVIDERS = {6: '午休', 10: '傍晚'}
    DIV_H    = 20

    @property
    def row_h(self):
        div_count = sum(1 for r in PERIODS if r[0] in self.DIVIDERS)
        avail = self._viewport_h() - self.HDR_H - div_count * self.DIV_H
        return max(1, avail // len(PERIODS))

    def _layout(self):
        rh = self.row_h
        y_cur = self.HDR_H
        items = []
        for ri, row in enumerate(PERIODS):
            pn = row[0]
            if pn in self.DIVIDERS:
                items.append(('div', y_cur, self.DIVIDERS[pn]))
                y_cur += self.DIV_H
            items.append(('row', y_cur, ri))
            y_cur += rh
        return rh, items

    def _col_w(self):
        if self.scroll:
            w = self.scroll.viewport().width()
        else:
            w = self.width()
        return max(60, (w - self.TIME_W) // 7)

    def _rebuild(self):
        for w in self._cards:
            w.deleteLater()
        self._cards = []

        col_w = self._col_w()
        placed, covered = {}, set()

        for c in self.courses:
            if self.week not in (c.get('week_list') or []):
                continue
            wd, ps, pe = c.get('weekday'), c.get('period_start'), c.get('period_end') or c.get('period_start')
            if not wd or ps is None:
                continue
            placed[(wd, ps)] = (c, (pe or ps) - ps + 1)
            for p in range(ps+1, (pe or ps)+1):
                covered.add((wd, p))

        eff_rh, layout = self._layout()
        pn_to_y = {PERIODS[ri][0]: y for kind, y, ri in layout if kind == 'row'}
        for (wd, pn), (c, span) in placed.items():
            y = pn_to_y.get(pn)
            if y is None: continue
            x = self.TIME_W + (wd-1) * col_w
            h = span * eff_rh - 4
            fg, bg = self.cmap.get(c.get('name',''), (C['accent'], C['surface']))
            self._cards.append(self._make_card(c, x+2, y+2, col_w-4, h, fg, bg))

        vh = self._viewport_h()
        self.setMinimumHeight(vh)
        self.setMaximumHeight(vh)
        self.setMinimumWidth(0)
        self.update()

    def _make_card(self, course, x, y, w, h, fg, bg):
        btn = QWidget(self)
        btn.setGeometry(x, y, w, h)
        btn.setCursor(Qt.CursorShape.PointingHandCursor)
        btn.setProperty('course', course)
        btn.setProperty('fg', fg)
        btn.setProperty('bg', bg)
        btn.show()

        def paint(event, b=btn, f=fg, bk=bg, c=course):
            p = QPainter(b)
            p.setRenderHint(QPainter.RenderHint.Antialiasing)
            r = b.rect().adjusted(0, 0, -1, -1)
            rh = r.height()

            path = QPainterPath()
            path.addRoundedRect(r.x(), r.y(), r.width(), r.height(), 5, 5)
            p.fillPath(path, QBrush(bk))

            bar = QPainterPath()
            bar.addRoundedRect(r.x(), r.y(), 3, r.height(), 2, 2)
            p.fillPath(bar, QBrush(f))

            p.setPen(QPen(f))
            p.setFont(QFont('Segoe UI', 10 if rh > 90 else 9, QFont.Weight.DemiBold))
            p.drawText(QRect(10, 6, r.width()-14, max(20, rh-30)),
                Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop |
                Qt.TextFlag.TextWordWrap, c.get('name',''))

            if rh > 55:
                p.setPen(QPen(QColor(f.red(), f.green(), f.blue(), 185)))
                p.setFont(QFont('Segoe UI', 8))
                p.drawText(QRect(10, r.bottom()-27, r.width()-12, 15),
                    Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter,
                    c.get('teacher',''))

            if rh > 74:
                p.setPen(QPen(QColor(f.red(), f.green(), f.blue(), 145)))
                p.setFont(QFont('Consolas', 8))
                p.drawText(QRect(10, r.bottom()-13, r.width()-12, 13),
                    Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter,
                    c.get('room',''))

        btn.paintEvent = paint

        def press(event, b=btn, self=self):
            if event.button() == Qt.MouseButton.LeftButton:
                c  = b.property('course')
                fg = b.property('fg')
                bg = b.property('bg')
                self._open_popup(c, fg, bg, b.mapToGlobal(QPoint(0,0)), b.width())
        btn.mousePressEvent = press
        return btn

    def _open_popup(self, course, fg, bg, card_pos, card_w):
        if self._popup:
            self._popup.hide()
            self._popup = None

        p = Popup(course, fg, bg)
        p.adjustSize()

        screen = QApplication.screenAt(card_pos) or QApplication.primaryScreen()
        sg = screen.availableGeometry()
        pw = p.sizeHint().width() + 20
        ph = p.sizeHint().height() + 20

        x = card_pos.x() + card_w + 6
        y = card_pos.y()
        if x + pw > sg.right():  x = card_pos.x() - pw - 6
        if y + ph > sg.bottom(): y = sg.bottom() - ph
        x = max(sg.left(), x)
        y = max(sg.top(), y)

        p.move(x, y)
        p.show()
        self._popup = p

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)

        col_w = self._col_w()
        rh    = self.row_h
        w     = self.width()
        dates = week_dates(self.week)
        today = datetime.now().date()

        p.fillRect(self.rect(), C['bg'])

        for di, d in enumerate(dates):
            if d.date() == today:
                p.fillRect(self.TIME_W + di*col_w, 0, col_w, self.height(), C['today_col'])

        p.fillRect(0, 0, w, self.HDR_H, C['header'])
        p.setPen(QPen(C['border']))
        p.drawLine(0, self.HDR_H-1, w, self.HDR_H-1)

        for di, day in enumerate(DAYS):
            d = dates[di]
            x = self.TIME_W + di*col_w
            is_today = d.date() == today

            if is_today:
                p.fillRect(x, 0, col_w, self.HDR_H, C['today_hdr'])

            p.setFont(QFont('Segoe UI', 10, QFont.Weight.DemiBold))
            p.setPen(QPen(C['accent'] if is_today else C['text']))
            p.drawText(QRect(x, 5, col_w, 22), Qt.AlignmentFlag.AlignCenter, day)

            date_str = f"{d.month}/{d.day:02d}"
            if is_today:
                pr = QRect(x + col_w//2 - 20, 28, 40, 17)
                pp = QPainterPath()
                pp.addRoundedRect(pr.x(), pr.y(), pr.width(), pr.height(), 8, 8)
                p.fillPath(pp, QBrush(C['accent']))
                p.setFont(QFont('Consolas', 9))
                p.setPen(QPen(QColor(255,255,255)))
            else:
                p.setFont(QFont('Consolas', 9))
                p.setPen(QPen(C['faint']))
            p.drawText(QRect(x, 28, col_w, 17), Qt.AlignmentFlag.AlignCenter, date_str)

        eff_rh, layout = self._layout()
        for item in layout:
            if item[0] == 'div':
                _, dy, label = item
                p.fillRect(0, dy, w, self.DIV_H, C['header'])
                p.setPen(QPen(C['border'], 1))
                p.drawLine(0, dy, w, dy)
                p.drawLine(0, dy + self.DIV_H - 1, w, dy + self.DIV_H - 1)
                p.setFont(QFont('Segoe UI', 8))
                p.setPen(QPen(C['faint']))
                p.drawText(QRect(0, dy, self.TIME_W, self.DIV_H),
                           Qt.AlignmentFlag.AlignCenter, label)
            else:
                _, y, ri = item
                row = PERIODS[ri]
                pn, pstart, pend = row[0], row[1], row[2]
                if SUMMER_MODE and len(row) >= 5:
                    pstart, pend = row[3], row[4]
                p.setPen(QPen(C['border'], 1))
                p.drawLine(0, y, w, y)
                block_h = 46
                top = y + (eff_rh - block_h) // 2
                p.setFont(QFont('Segoe UI', 10, QFont.Weight.DemiBold))
                p.setPen(QPen(C['muted']))
                p.drawText(QRect(0, top, self.TIME_W, 18), Qt.AlignmentFlag.AlignCenter, str(pn))
                p.setFont(QFont('Consolas', 8))
                p.setPen(QPen(C['faint']))
                p.drawText(QRect(0, top+18, self.TIME_W, 14), Qt.AlignmentFlag.AlignCenter, pstart)
                p.drawText(QRect(0, top+32, self.TIME_W, 14), Qt.AlignmentFlag.AlignCenter, pend)
                p.setPen(QPen(C['border'], 1))
                for ci in range(8):
                    p.drawLine(self.TIME_W + ci*col_w, y, self.TIME_W + ci*col_w, y+eff_rh)
        last_y = [item[1] for item in layout if item[0]=='row'][-1]
        bot = last_y + eff_rh
        p.setPen(QPen(C['border']))
        p.drawLine(0, bot, w, bot)
        p.drawLine(self.TIME_W, 0, self.TIME_W, bot)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if self.courses:
            self._rebuild()


# ═══════════════════════════════════════════════
#  解析逻辑（整合自 parse_schedule.py）
# ═══════════════════════════════════════════════
import re as _re

def _parse_weeks(s):
    wl = []
    for part in _re.split(r'[,，]', s):
        part = part.strip()
        m = _re.match(r'(\d+)-(\d+)周', part)
        if m:
            wl += list(range(int(m.group(1)), int(m.group(2))+1))
        else:
            m = _re.match(r'(\d+)周', part)
            if m: wl.append(int(m.group(1)))
    return sorted(set(wl))


def _parse_cell(text):
    """
    解析单元格文本，兼容两种格式：
    表格视图: '编译原理■ (1-3节)1-16周 啬园校区  JX03-313  顾卫江 ...'
    列表视图: '编译原理■ 周数：1-16周 校区:啬园校区 上课地点：JX03-313  教师 ：顾卫江 ...'
    """
    # 过滤无效行
    skip_exact = ['课程名称', '没有符合', '无数据', '共 0 页', '课表信息', '节次', '时间段']
    skip_start = ['学年第', '实践课程', '申请', '申报', '教学单位', '开放时间', '指导教师']
    for s in skip_exact:
        if s in text: return None
    for s in skip_start:
        if text.startswith(s): return None
    if _re.search(r'学号[：:]|注[：:]|[■◆▲]-', text): return None
    if text.strip() in ['上午', '下午', '晚上'] or _re.match(r'^星期', text): return None

    # 提取课程名（去掉末尾■◆▲及空格）
    name_m = _re.match(r'^(.+?)[■◆▲\s]', text)
    if not name_m: return None
    name = name_m.group(1).strip()
    if len(name) < 2 or len(name) > 50: return None
    if _re.match(r'^[\d\s]+$', name): return None

    teacher = room = location = weeks_raw = periods_raw = ''

    # ── 列表视图格式（含「周数：」「上课地点：」「教师 ：」）──
    if '周数：' in text or '上课地点：' in text:
        m = _re.search(r'周数[：:]\s*([^\s]+)', text)
        if m: weeks_raw = m.group(1)
        m = _re.search(r'上课地点[：:]\s*(\S+)', text)
        if m: room = m.group(1)
        m = _re.search(r'校区[：:]\s*(\S+校区)', text)
        if m: location = m.group(1)
        m = _re.search(r'教师\s*[：:]\s*(\S+)', text)
        if m: teacher = m.group(1)
        # 列表视图没有节次信息，period 留空

    # ── 表格视图格式（含「(N-M节)」）──
    else:
        m = _re.search(r'\((\d+-?\d*节)\)\s*([^\s]+)', text)
        if m:
            periods_raw = m.group(1)
            weeks_raw   = m.group(2)
        # 校区 + 房间（「啬园校区  JX03-313」）
        m = _re.search(r'(\S+校区)\s+(\S+)', text)
        if m:
            location = m.group(1)
            room     = m.group(2)
        # 教师：紧跟房间后的2-5个汉字（支持多个空格）
        m = _re.search(r'[A-Z]{1,3}\d{2}-\d{3}\S*\s+([\u4e00-\u9fa5]{2,5})(?:\s|$)', text)
        if not m:
            m = _re.search(r'楼\S+\s+([\u4e00-\u9fa5]{2,5})(?:\s|$)', text)
        if m: teacher = m.group(1)

    ps = pe = None
    if periods_raw:
        m = _re.match(r'(\d+)-(\d+)节', periods_raw)
        if m: ps, pe = int(m.group(1)), int(m.group(2))
        else:
            m = _re.match(r'(\d+)节', periods_raw)
            if m: ps = pe = int(m.group(1))

    if not weeks_raw: return None

    return {"name": name, "teacher": teacher or "未知", "room": room or "未知",
            "location": location or "未知", "periods": periods_raw or "未知",
            "period_start": ps, "period_end": pe, "weeks": weeks_raw or "未知",
            "week_list": _parse_weeks(weeks_raw) if weeks_raw else [],
            "raw": text}

def _parse_html(html):
    """从页面 HTML 解析课程，兼容南通大学教务系统表格/列表双视图"""
    from html.parser import HTMLParser

    class TableParser(HTMLParser):
        def __init__(self):
            super().__init__()
            self.tables = []
            self._stack = []
            self._cur_row = None
            self._cell_attrs = {}
            self._text = None
        def handle_starttag(self, tag, attrs):
            attrs = dict(attrs)
            if tag == 'table':
                self._stack.append([])
            elif tag == 'tr' and self._stack:
                self._cur_row = []
            elif tag in ('td','th') and self._stack:
                self._text = ''
                self._cell_attrs = attrs
            elif tag == 'br' and self._text is not None:
                self._text += ' '
        def handle_endtag(self, tag):
            if tag == 'table' and self._stack:
                self.tables.append(self._stack.pop())
            elif tag == 'tr' and self._cur_row is not None and self._stack:
                self._stack[-1].append(self._cur_row)
                self._cur_row = None
            elif tag in ('td','th') and self._cur_row is not None and self._text is not None:
                t = ' '.join(self._text.split())  # 合并空白
                rs = int(self._cell_attrs.get('rowspan', 1))
                cs = int(self._cell_attrs.get('colspan', 1))
                self._cur_row.append({'text': t, 'rs': rs, 'cs': cs})
                self._text = None
        def handle_data(self, data):
            if self._text is not None:
                self._text += data
        def handle_entityref(self, name):
            if self._text is not None and name == 'nbsp':
                self._text += ' '
        def handle_charref(self, name):
            if self._text is not None:
                try:
                    n = int(name[1:], 16) if name.startswith('x') else int(name)
                    self._text += chr(n)
                except: pass

    p = TableParser()
    p.feed(html)
    if not p.tables: return []

    DAY_MAP = {'星期一':1,'星期二':2,'星期三':3,'星期四':4,'星期五':5,'星期六':6,'星期日':7,'星期天':7}
    WN = {1:'周一',2:'周二',3:'周三',4:'周四',5:'周五',6:'周六',7:'周日'}

    # 找含星期表头的课程表格（优先），没有就用最大的
    sched_table = None
    for t in p.tables:
        for row in t[:3]:
            if any(k in cell['text'] for cell in row for k in DAY_MAP):
                sched_table = t; break
        if sched_table: break
    if not sched_table:
        sched_table = max(p.tables, key=lambda t: sum(len(r) for r in t))

    # 解析列头 → weekday
    col_wd = {}
    for row in sched_table[:3]:
        for ci, cell in enumerate(row):
            for k, v in DAY_MAP.items():
                if k in cell['text']: col_wd[ci] = v; break
        if col_wd: break

    # 展开 rowspan/colspan
    grid = {}
    for ri, row in enumerate(sched_table):
        ci = 0
        for cell in row:
            while (ri, ci) in grid: ci += 1
            for dr in range(cell['rs']):
                for dc in range(cell['cs']):
                    grid[(ri+dr, ci+dc)] = cell['text']
            ci += cell['cs']

    courses, seen = [], set()
    for (ri, ci), text in sorted(grid.items()):
        if ri == 0: continue
        text = text.strip()
        if len(text) < 4: continue
        c = _parse_cell(text)
        if not c: continue
        key = c['name'] + c['teacher'] + c['room']
        if key in seen: continue
        seen.add(key)
        c['weekday'] = col_wd.get(ci)
        c['weekday_name'] = WN.get(c['weekday'], '未知')
        courses.append(c)

    # 如果表格视图解析失败，降级用所有单元格扫描（列表视图）
    if not courses:
        seen2 = set()
        for t in p.tables:
            for row in t:
                for cell in row:
                    text = cell['text'].strip()
                    if len(text) < 4: continue
                    c = _parse_cell(text)
                    if not c: continue
                    key = c['name'] + c['teacher'] + c['room']
                    if key in seen2: continue
                    seen2.add(key)
                    c['weekday'] = None
                    c['weekday_name'] = '未知'
                    courses.append(c)

    return courses


# ═══════════════════════════════════════════════
#  内置浏览器导入窗口
# ═══════════════════════════════════════════════
class ImportDialog(QDialog):
    courses_imported = pyqtSignal()

    TARGET_URL = "https://tdjw.ntu.edu.cn/"

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("导入课表 — 南通大学教务系统")
        self.resize(1000, 700)
        self.setMinimumSize(800, 560)
        self.setModal(True)
        self._build()

    def _build(self):
        self.setStyleSheet(f"background:{rgb(C['bg'])};")
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # ── 顶部工具栏 ──
        bar = QWidget(); bar.setFixedHeight(48)
        def bar_paint(e, b=bar):
            p = QPainter(b); p.fillRect(b.rect(), C['surface'])
            p.setPen(QPen(C['border'])); p.drawLine(0, b.height()-1, b.width(), b.height()-1)
        bar.paintEvent = bar_paint
        bl = QHBoxLayout(bar); bl.setContentsMargins(16, 0, 16, 0); bl.setSpacing(10)

        self._status_lbl = QLabel("请登录教务系统，查询课程表后点击「导入课表」")
        self._status_lbl.setFont(QFont('Segoe UI', 9))
        self._status_lbl.setStyleSheet(f"color:{rgb(C['muted'])};")
        bl.addWidget(self._status_lbl, 1)

        self._import_btn = QPushButton("导入课表")
        self._import_btn.setFixedSize(100, 32)
        self._import_btn.setFont(QFont('Segoe UI', 9, QFont.Weight.DemiBold))
        self._import_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self._import_btn.setStyleSheet(
            f"QPushButton {{ background:{rgb(C['accent'])}; border:none; border-radius:8px; color:white; }}"
            f"QPushButton:hover {{ background:rgb(185,82,55); }}"
            f"QPushButton:disabled {{ background:{rgb(C['faint'])}; }}")
        self._import_btn.clicked.connect(self._do_import)
        bl.addWidget(self._import_btn)

        root.addWidget(bar)

        # ── WebEngine 浏览器 ──
        try:
            from PyQt6.QtWebEngineWidgets import QWebEngineView
            from PyQt6.QtCore import QUrl
            from PyQt6.QtWebEngineCore import QWebEnginePage

            class _Page(QWebEnginePage):
                def createWindow(self, _type):
                    # 新标签页在同一视图内打开
                    return self

            self._view = QWebEngineView()
            self._view.setPage(_Page(self._view))
            self._view.load(QUrl(self.TARGET_URL))
            root.addWidget(self._view, 1)
            self._has_webengine = True
        except Exception as _we_err:
            self._has_webengine = False
            fallback = QWidget()
            fl = QVBoxLayout(fallback); fl.setAlignment(Qt.AlignmentFlag.AlignCenter)
            msg = QLabel(f"内置浏览器加载失败：\n{_we_err}")
            msg.setFont(QFont('Segoe UI', 10)); msg.setAlignment(Qt.AlignmentFlag.AlignCenter)
            msg.setWordWrap(True)
            msg.setStyleSheet(f"color:{rgb(C['muted'])};")
            fl.addWidget(msg)
            root.addWidget(fallback, 1)

    def _do_import(self):
        if not self._has_webengine: return
        self._import_btn.setEnabled(False)
        self._import_btn.setText("解析中…")
        self._status_lbl.setText("正在读取页面…")
        # 用 JS 直接拿渲染后的完整 HTML，确保动态内容已加载
        self._view.page().runJavaScript(
            "document.documentElement.outerHTML",
            self._on_html
        )

    def _on_html(self, html):
        try:
            courses = _parse_html(html)
        except Exception as e:
            self._status_lbl.setText(f"解析出错：{e}")
            self._import_btn.setEnabled(True)
            self._import_btn.setText("导入课表")
            return
        if not courses:
            self._status_lbl.setText("未找到课程表，请确认已查询完整课表后再导入")
            self._import_btn.setEnabled(True)
            self._import_btn.setText("重试")
            return
        path = os.path.join(_app_dir(), 'schedule.json')
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(courses, f, ensure_ascii=False, indent=2)
        self._status_lbl.setText(f"成功导入 {len(courses)} 门课程！")
        self._import_btn.setText("关闭")
        self._import_btn.setEnabled(True)
        self._import_btn.setStyleSheet(
            f"QPushButton {{ background:none; border:1px solid {rgb(C['border'])};"
            f" border-radius:8px; color:{rgb(C['muted'])}; }}"
            f"QPushButton:hover {{ border-color:{rgb(C['accent'])}; color:{rgb(C['accent'])}; }}")
        self._import_btn.clicked.disconnect()
        self._import_btn.clicked.connect(self.close)
        self.courses_imported.emit()


# ═══════════════════════════════════════════════
#  设置弹窗
# ═══════════════════════════════════════════════
class _Toggle(QWidget):
    toggled = pyqtSignal(bool)

    def __init__(self, checked=False, parent=None):
        super().__init__(parent)
        self._checked  = checked
        self._anim_val = 1.0 if checked else 0.0
        self.setFixedSize(48, 28)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self._anim = QVariantAnimation(self)
        self._anim.setDuration(180)
        self._anim.setEasingCurve(QEasingCurve.Type.OutCubic)
        self._anim.valueChanged.connect(lambda v: (setattr(self,'_anim_val',v), self.update()))

    def paintEvent(self, e):
        p = QPainter(self); p.setRenderHint(QPainter.RenderHint.Antialiasing)
        t = self._anim_val
        bc, ac = C['border'], C['accent']
        track = QColor(int(bc.red()+(ac.red()-bc.red())*t),
                       int(bc.green()+(ac.green()-bc.green())*t),
                       int(bc.blue()+(ac.blue()-bc.blue())*t))
        p.setBrush(QBrush(track)); p.setPen(Qt.PenStyle.NoPen)
        p.drawRoundedRect(0, 4, 48, 20, 10, 10)
        x = int(4 + t * 20)
        p.setBrush(QBrush(QColor(0,0,0,20))); p.drawEllipse(x, 3, 22, 22)
        p.setBrush(QBrush(QColor(255,255,255))); p.drawEllipse(x, 2, 22, 22)

    def mousePressEvent(self, e):
        if e.button() == Qt.MouseButton.LeftButton:
            self._checked = not self._checked
            self._anim.stop()
            self._anim.setStartValue(self._anim_val)
            self._anim.setEndValue(1.0 if self._checked else 0.0)
            self._anim.start()
            self.toggled.emit(self._checked)


class SettingsDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("设置")
        self.setFixedSize(360, 260)
        self.setModal(True)
        self._build()

    def _build(self):
        self.setStyleSheet(f"background:{rgb(C['surface'])};")
        root = QVBoxLayout(self)
        root.setContentsMargins(28, 24, 28, 24)
        root.setSpacing(0)

        t = QLabel("设置")
        t.setFont(QFont('Segoe UI', 13, QFont.Weight.DemiBold))
        t.setStyleSheet(f"color:{rgb(C['text'])};")
        root.addWidget(t)
        root.addSpacing(20)

        row = QHBoxLayout(); row.setSpacing(0)
        left = QVBoxLayout(); left.setSpacing(2)
        lbl = QLabel("夏令时模式"); lbl.setFont(QFont('Segoe UI', 10))
        lbl.setStyleSheet(f"color:{rgb(C['text'])};")
        sub = QLabel("下午课程整体推迟 30 分钟"); sub.setFont(QFont('Segoe UI', 8))
        sub.setStyleSheet(f"color:{rgb(C['muted'])};")
        left.addWidget(lbl); left.addWidget(sub)
        tog = _Toggle(checked=SUMMER_MODE)
        tog.toggled.connect(self._on_toggle)
        row.addLayout(left, 1)
        row.addWidget(tog, alignment=Qt.AlignmentFlag.AlignVCenter)
        root.addLayout(row)
        root.addSpacing(20)

        # 分隔线
        sep = QFrame(); sep.setFrameShape(QFrame.Shape.HLine)
        sep.setStyleSheet(f"color:{rgb(C['border'])};")
        root.addWidget(sep)
        root.addSpacing(16)

        # 删除课表
        del_row = QHBoxLayout(); del_row.setSpacing(0)
        del_left = QVBoxLayout(); del_left.setSpacing(2)
        del_lbl = QLabel("删除课表数据"); del_lbl.setFont(QFont('Segoe UI', 10))
        del_lbl.setStyleSheet(f"color:{rgb(C['text'])};")
        del_sub = QLabel("清除已导入的全部课程"); del_sub.setFont(QFont('Segoe UI', 8))
        del_sub.setStyleSheet(f"color:{rgb(C['muted'])};")
        del_left.addWidget(del_lbl); del_left.addWidget(del_sub)
        del_btn = QPushButton("删除"); del_btn.setFixedSize(64, 28)
        del_btn.setFont(QFont('Segoe UI', 9))
        del_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        del_btn.setStyleSheet(
            f"QPushButton {{ background:none; border:1px solid {rgb(C['border'])};"
            f" border-radius:6px; color:{rgb(C['muted'])}; }}"
            f"QPushButton:hover {{ border-color:#c0392b; color:#c0392b; }}")
        del_btn.clicked.connect(self._del_schedule)
        del_row.addLayout(del_left, 1)
        del_row.addWidget(del_btn, alignment=Qt.AlignmentFlag.AlignVCenter)
        root.addLayout(del_row)

        root.addStretch()

        btn_row = QHBoxLayout(); btn_row.addStretch()
        done = QPushButton("完成"); done.setFixedSize(80, 32)
        done.setFont(QFont('Segoe UI', 9, QFont.Weight.DemiBold))
        done.setCursor(Qt.CursorShape.PointingHandCursor)
        done.setStyleSheet(
            f"QPushButton {{ background:{rgb(C['accent'])}; border:none; border-radius:8px; color:white; }}"
            f"QPushButton:hover {{ background:rgb(185,82,55); }}")
        done.clicked.connect(self.close)
        btn_row.addWidget(done)
        root.addLayout(btn_row)

    def _on_toggle(self, checked):
        global SUMMER_MODE; SUMMER_MODE = checked
        w = self.parent()
        while w and not isinstance(w, QMainWindow):
            w = w.parent() if hasattr(w, 'parent') else None
        if w: w._refresh()

    def _del_schedule(self):
        # 自定义确认弹窗
        dlg = QDialog(self)
        dlg.setWindowTitle("确认删除")
        dlg.setFixedSize(300, 148)
        dlg.setWindowFlag(Qt.WindowType.WindowContextHelpButtonHint, False)
        dlg.setStyleSheet(f"background:{rgb(C['surface'])};")
        v = QVBoxLayout(dlg)
        v.setContentsMargins(28, 24, 28, 20)
        v.setSpacing(6)
        t = QLabel("确定要删除全部课表数据吗？")
        t.setFont(QFont('Segoe UI', 10, QFont.Weight.DemiBold))
        t.setStyleSheet(f"color:{rgb(C['text'])};")
        s = QLabel("此操作不可撤销。")
        s.setFont(QFont('Segoe UI', 9))
        s.setStyleSheet(f"color:{rgb(C['muted'])};")
        v.addWidget(t); v.addWidget(s); v.addStretch()
        br = QHBoxLayout(); br.addStretch(); br.setSpacing(8)
        cancel = QPushButton("取消"); cancel.setFixedSize(72, 30)
        cancel.setFont(QFont('Segoe UI', 9))
        cancel.setCursor(Qt.CursorShape.PointingHandCursor)
        cancel.setStyleSheet(
            f"QPushButton {{ background:none; border:1px solid {rgb(C['border'])};"
            f" border-radius:6px; color:{rgb(C['muted'])}; }}"
            f"QPushButton:hover {{ border-color:{rgb(C['accent'])}; color:{rgb(C['accent'])}; }}")
        cancel.clicked.connect(dlg.reject)
        confirm = QPushButton("删除"); confirm.setFixedSize(72, 30)
        confirm.setFont(QFont('Segoe UI', 9, QFont.Weight.DemiBold))
        confirm.setCursor(Qt.CursorShape.PointingHandCursor)
        confirm.setStyleSheet(
            "QPushButton { background:#c0392b; border:none; border-radius:6px; color:white; }"
            "QPushButton:hover { background:#a93226; }")
        confirm.clicked.connect(dlg.accept)
        br.addWidget(cancel); br.addWidget(confirm)
        v.addLayout(br)
        if dlg.exec() == QDialog.DialogCode.Accepted:
            p = os.path.join(_app_dir(), 'schedule.json')
            if os.path.exists(p):
                os.remove(p)
            # 找到 MainWindow 刷新
            w = self.parent()
            while w is not None:
                if isinstance(w, QMainWindow): break
                w = w.parent() if callable(w.parent) else None
            if w:
                w.courses = []
                w._refresh()


# ═══════════════════════════════════════════════
#  主窗口
# ═══════════════════════════════════════════════
class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle('光流 TimeFlow')
        icon_path = os.path.join(_res_dir(), 'logo.svg')
        if os.path.exists(icon_path):
            self.setWindowIcon(QIcon(icon_path))
        self.resize(1120, 740)
        self.setMinimumSize(780, 750)

        self.courses = load_json()
        self.week    = current_week()
        self.cmap    = {}
        self._assign_colors()
        self._build()
        self._refresh()

    def _assign_colors(self):
        for c in self.courses:
            n = c.get('name','')
            if n and n not in self.cmap:
                self.cmap[n] = CARD_COLORS[len(self.cmap) % len(CARD_COLORS)]

    def _build(self):
        root = QWidget()
        self.setCentralWidget(root)
        vbox = QVBoxLayout(root)
        vbox.setContentsMargins(0,0,0,0)
        vbox.setSpacing(0)

        vbox.addWidget(self._topbar())
        vbox.addWidget(self._statsbar())

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setStyleSheet("QScrollBar { width:0; height:0; }")
        self.grid = Grid()
        self.grid.scroll = scroll

        # 视口大小变化时重建网格
        class _VPFilter(QObject):
            def __init__(self, grid):
                super().__init__()
                self._grid = grid
            def eventFilter(self, obj, event):
                if event.type() == QEvent.Type.Resize:
                    self._grid._rebuild()
                return False
        self._vpf = _VPFilter(self.grid)
        scroll.viewport().installEventFilter(self._vpf)

        scroll.setWidget(self.grid)
        vbox.addWidget(scroll)

    # ── 顶栏 ──
    def _topbar(self):
        bar = QWidget()
        bar.setFixedHeight(64)

        def paint(e, b=bar):
            p = QPainter(b)
            p.fillRect(b.rect(), C['surface'])
            p.setPen(QPen(C['border']))
            p.drawLine(0, b.height()-1, b.width(), b.height()-1)
        bar.paintEvent = paint

        h = QHBoxLayout(bar)
        h.setContentsMargins(24, 0, 24, 0)

        logo_path = os.path.join(_res_dir(), 'logo.svg')
        if os.path.exists(logo_path):
            from PyQt6.QtSvgWidgets import QSvgWidget
            svg = QSvgWidget(logo_path)
            svg.setFixedSize(34, 34)
            svg_container = svg
        else:
            svg_container = QWidget()
            svg_container.setFixedSize(34, 34)
            svg_container.setStyleSheet(f"background:{rgb(C['accent'])}; border-radius:10px;")

        title = QLabel('光流 TimeFlow')
        title.setFont(QFont('Segoe UI', 13, QFont.Weight.DemiBold))
        title.setStyleSheet(f"color:{rgb(C['text'])};")

        logo = QHBoxLayout()
        logo.setSpacing(10)
        logo.addWidget(svg_container)
        logo.addWidget(title)
        h.addLayout(logo)
        h.addStretch()

        self._week_lbl = QLabel(f'第 {self.week} 周')
        self._week_lbl.setFont(QFont('Segoe UI', 11))
        self._week_lbl.setStyleSheet(f"color:{rgb(C['muted'])};")
        self._week_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._week_lbl.setFixedWidth(84)

        h.addWidget(self._nav_btn('‹', lambda: self._change(-1)))
        h.addWidget(self._week_lbl)
        h.addWidget(self._nav_btn('›', lambda: self._change(+1)))
        h.addStretch()

        btn = QPushButton('本周')
        btn.setFont(QFont('Segoe UI', 9))
        btn.setFixedHeight(34)
        btn.setCursor(Qt.CursorShape.PointingHandCursor)
        btn.setStyleSheet(f"""
            QPushButton {{
                background: none;
                border: 1px solid {rgb(C['border'])};
                border-radius: 7px;
                color: {rgb(C['muted'])};
                padding: 0 16px;
            }}
            QPushButton:hover {{
                border-color: {rgb(C['accent'])};
                color: {rgb(C['accent'])};
            }}
        """)
        btn.clicked.connect(self._go_today)
        h.addWidget(btn)

        imp_btn = QPushButton('导入课表')
        imp_btn.setFont(QFont('Segoe UI', 9, QFont.Weight.DemiBold))
        imp_btn.setFixedHeight(34)
        imp_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        imp_btn.setStyleSheet(f"""
            QPushButton {{
                background: {rgb(C['accent'])};
                border: none;
                border-radius: 7px;
                color: white;
                padding: 0 16px;
            }}
            QPushButton:hover {{ background: rgb(185,82,55); }}
        """)
        imp_btn.clicked.connect(self._open_import)
        h.addSpacing(8)
        h.addWidget(imp_btn)

        # 设置按钮
        h.addSpacing(8)
        set_btn = QPushButton('设置')
        set_btn.setFont(QFont('Segoe UI', 9))
        set_btn.setFixedHeight(34)
        set_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        set_btn.setStyleSheet(f"""
            QPushButton {{
                background: none;
                border: 1px solid {rgb(C['border'])};
                border-radius: 7px;
                color: {rgb(C['muted'])};
                padding: 0 14px;
            }}
            QPushButton:hover {{
                border-color: {rgb(C['accent'])};
                color: {rgb(C['accent'])};
            }}
        """)
        set_btn.clicked.connect(self._open_settings)
        h.addWidget(set_btn)
        return bar

    def _nav_btn(self, text, slot):
        btn = QPushButton(text)
        btn.setFixedSize(34, 34)
        btn.setFont(QFont('Segoe UI', 14))
        btn.setCursor(Qt.CursorShape.PointingHandCursor)
        btn.setStyleSheet(f"""
            QPushButton {{
                background: none;
                border: 1px solid {rgb(C['border'])};
                border-radius: 7px;
                color: {rgb(C['muted'])};
            }}
            QPushButton:hover {{
                border-color: {rgb(C['accent'])};
                color: {rgb(C['accent'])};
            }}
        """)
        btn.clicked.connect(slot)
        return btn

    # ── 统计栏 ──
    def _statsbar(self):
        bar = QWidget()
        bar.setFixedHeight(38)

        def paint(e, b=bar):
            p = QPainter(b)
            p.fillRect(b.rect(), C['header'])
            p.setPen(QPen(C['border']))
            p.drawLine(0, b.height()-1, b.width(), b.height()-1)
        bar.paintEvent = paint

        self._stats_lay = QHBoxLayout(bar)
        self._stats_lay.setContentsMargins(24, 0, 24, 0)
        self._stats_lay.setSpacing(32)
        return bar

    def _refresh_stats(self):
        while self._stats_lay.count():
            item = self._stats_lay.takeAt(0)
            if item.widget(): item.widget().deleteLater()

        wc   = [c for c in self.courses if self.week in (c.get('week_list') or [])]
        pts  = sum((c.get('period_end',0) or 0) - (c.get('period_start',0) or 0) + 1 for c in wc)

        for val, lbl in [
            (f'{len(wc)} 门课', '本周'),
            (f'{pts} 节',       '课时'),
            (datetime.now().strftime('%m/%d'), '今日'),
        ]:
            w = QWidget()
            lay = QHBoxLayout(w)
            lay.setContentsMargins(0,0,0,0)
            lay.setSpacing(6)
            v = QLabel(val)
            v.setFont(QFont('Segoe UI', 9, QFont.Weight.DemiBold))
            v.setStyleSheet(f"color:{rgb(C['accent'])};")
            l = QLabel(lbl)
            l.setFont(QFont('Segoe UI', 9))
            l.setStyleSheet(f"color:{rgb(C['muted'])};")
            lay.addWidget(v)
            lay.addWidget(l)
            self._stats_lay.addWidget(w)

        self._stats_lay.addStretch()

    def _refresh(self):
        self._week_lbl.setText(f'第 {self.week} 周')
        self._refresh_stats()
        self.grid.setup(self.courses, self.week, self.cmap)

    def _change(self, d):
        self.week = max(1, min(20, self.week + d))
        self._refresh()

    def _go_today(self):
        self.week = current_week()
        self._refresh()

    def _open_settings(self):
        dlg = SettingsDialog(self)
        dlg.exec()

    def _open_import(self):
        dlg = ImportDialog(self)
        dlg.courses_imported.connect(self._reload_courses)
        dlg.exec()

    def _reload_courses(self):
        self.courses = load_json()
        self.cmap = {}
        self._assign_colors()
        self._refresh()

    @staticmethod
    def _gear_icon(p, s, color):
        """绘制齿轮SVG路径"""
        cx, cy, r_out, r_in = s/2, s/2, s*0.28, s*0.13
        teeth = 8
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QBrush(color))
        path = QPainterPath()
        import math
        step = 2 * math.pi / teeth
        tooth_h = s * 0.07
        pts = []
        for i in range(teeth):
            a0 = i * step - step*0.3
            a1 = i * step - step*0.1
            a2 = i * step + step*0.1
            a3 = i * step + step*0.3
            pts += [
                (cx + r_out * math.cos(a0), cy + r_out * math.sin(a0)),
                (cx + (r_out+tooth_h)*math.cos(a1), cy + (r_out+tooth_h)*math.sin(a1)),
                (cx + (r_out+tooth_h)*math.cos(a2), cy + (r_out+tooth_h)*math.sin(a2)),
                (cx + r_out * math.cos(a3), cy + r_out * math.sin(a3)),
            ]
        path.moveTo(*pts[0])
        for pt in pts[1:]:
            path.lineTo(*pt)
        path.closeSubpath()
        hole = QPainterPath()
        hole.addEllipse(cx - r_in, cy - r_in, r_in*2, r_in*2)
        gear = path.subtracted(hole)
        p.drawPath(gear)

    def keyPressEvent(self, e):
        if e.key() == Qt.Key.Key_Left:  self._change(-1)
        if e.key() == Qt.Key.Key_Right: self._change(+1)
        if e.key() == Qt.Key.Key_Escape:
            if self.grid._popup:
                self.grid._popup.hide()
                self.grid._popup = None

if __name__ == '__main__':
    try:
        from PyQt6.QtWebEngineWidgets import QWebEngineView  # noqa
        QApplication.setAttribute(Qt.ApplicationAttribute.AA_ShareOpenGLContexts)
    except Exception:
        pass
    app = QApplication(sys.argv)
    app.setStyle('windowsvista')
    win = MainWindow()
    win.show()
    sys.exit(app.exec())