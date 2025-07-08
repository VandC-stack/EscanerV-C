import pandas as pd
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from config.database import DatabaseManager

def importar_historico(ruta_excel):
    db = DatabaseManager()
    df = pd.read_excel(ruta_excel, sheet_name=0, dtype=str)
    actualizados = 0
    no_encontrados = 0
    for idx, row in df.iterrows():
        item = str(row.iloc[0]).strip()
        resultado = str(row.iloc[1]).strip() if len(row) > 1 else ''
        if not item or item.lower() == 'item':
            continue
        # Actualizar solo si el item existe en codigos_items
        existe = db.execute_query("SELECT 1 FROM codigos_items WHERE item = %s", (item,))
        if existe:
            db.execute_query(
                "UPDATE codigos_items SET resultado = %s, fecha_actualizacion = NOW() WHERE item = %s",
                (resultado, item),
                fetch=False
            )
            actualizados += 1
        else:
            no_encontrados += 1
    print(f"Actualizados: {actualizados}")
    print(f"No encontrados en CLP: {no_encontrados}")

if __name__ == "__main__":
    ruta = r"C:\Users\bost2\OneDrive\Escritorio\MODELOS CUMPLIENDO (004).xlsx"
    importar_historico(ruta) 