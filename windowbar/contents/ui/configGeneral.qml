import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_rows: rowsCombo.currentIndex
    property alias cfg_maxLabelWidth: labelWidth.value
    property alias cfg_showOnlyCurrentDesktop: currentDesktop.checked

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: rowsCombo
            Kirigami.FormData.label: "Rows:"
            // Index == config value: 0 = automatic.
            model: ["Automatic", "1", "2", "3"]
        }
        QQC2.SpinBox {
            id: labelWidth
            Kirigami.FormData.label: "Maximum button width:"
            from: 6
            to: 40
        }
        QQC2.CheckBox {
            id: currentDesktop
            Kirigami.FormData.label: "Show:"
            text: "Only windows on the current desktop"
        }
    }
}
