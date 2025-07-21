"""
graficas.py - Utilidades para validación y graficado de evolución mensual de capturas y consultas.
"""

import numpy as np
import matplotlib.pyplot as plt
import mplcursors

from graficas import crear_grafica_evolucion, validar_datos_grafica  # Si están en este archivo, omite esta línea

def validar_datos_grafica(meses, capturas, consultas):
    """
    Valida que los datos para la gráfica sean correctos.
    Lanza TypeError o ValueError si hay problemas.
    """
    if not (isinstance(meses, list) and isinstance(capturas, list) and isinstance(consultas, list)):
        raise TypeError("Todos los argumentos deben ser listas.")
    if not (len(meses) == len(capturas) == len(consultas)):
        raise ValueError("Las listas deben tener la misma longitud.")
    if len(meses) == 0:
        raise ValueError("Las listas no pueden estar vacías.")
    if not all(isinstance(m, str) for m in meses):
        raise TypeError("Todos los meses deben ser cadenas de texto.")
    if not all(isinstance(x, (int, float)) for x in capturas + consultas):
        raise TypeError("Todos los valores de capturas y consultas deben ser numéricos.")

def crear_grafica_evolucion(meses, capturas, consultas):
    """
    Genera una figura de matplotlib con la evolución mensual de capturas y consultas.
    Devuelve (fig, ax, lineas) para uso interactivo o exportación.
    """
    validar_datos_grafica(meses, capturas, consultas)
    fig, ax = plt.subplots(figsize=(10, 4))
    ax.set_facecolor('#000000')
    fig.patch.set_facecolor('#000000')
    linea_capturas = ax.plot(meses, capturas, marker='o', label='Capturas', color='#00FFAA', linewidth=2.5, markerfacecolor='#00FFAA', markeredgewidth=0)
    linea_consultas = ax.plot(meses, consultas, marker='s', label='Consultas', color='#55DDFF', linewidth=2.5, markerfacecolor='#55DDFF', markeredgewidth=0)
    ax.set_title('Grafico mensual de capturas y consultas (últimos 12 meses)', fontsize=15, color='#00FFAA', pad=10, fontname='Segoe UI')
    ax.set_xlabel('Mes', fontsize=13, color='#00FFAA', fontname='Segoe UI')
    ax.set_ylabel('Cantidad', fontsize=13, color='#00FFAA', fontname='Segoe UI')
    ax.tick_params(axis='x', colors='#FFFFFF', labelsize=10)
    ax.tick_params(axis='y', colors='#FFFFFF', labelsize=10)
    ax.spines['bottom'].set_color('#00FFAA')
    ax.spines['left'].set_color('#00FFAA')
    ax.spines['top'].set_color('#000000')
    ax.spines['right'].set_color('#000000')
    ax.legend(facecolor='#111111', edgecolor='#111111', fontsize=12, loc='upper left', labelcolor='#00FFAA')
    ax.grid(True, linestyle='--', alpha=0.18, color='#55DDFF')
    plt.xticks(rotation=30)
    return fig, ax, (linea_capturas, linea_consultas)

def mostrar_grafica_evolucion_interactiva(meses, capturas, consultas):
    """
    Muestra de manera interactiva y eficiente la gráfica de la evolución mensual de capturas y consultas.
    Utiliza numpy para un acceso rápido y un solo cursor que funcione para ambas líneas.
    """
    try:
        # Convertir a numpy para acceso rápido y seguro
        meses = np.array(meses)
        capturas = np.array(capturas)
        consultas = np.array(consultas)

        fig, ax, (linea_capturas, linea_consultas) = crear_grafica_evolucion(meses, capturas, consultas)
        # Un solo cursor para ambas líneas
        lines = linea_capturas + linea_consultas
        cursor = mplcursors.cursor(lines, hover=True)

        @cursor.connect("add")
        def on_add(sel):
            idx = int(sel.index)
            if sel.artist in linea_capturas:
                sel.annotation.set_text(f"Capturas: {capturas[idx]}\nMes: {meses[idx]}")
            else:
                sel.annotation.set_text(f"Consultas: {consultas[idx]}\nMes: {meses[idx]}")

        fig.show()
    except (TypeError, ValueError) as e:
        print(f"Error en los datos de la gráfica: {e}")
    except Exception as e:
        print(f"Error inesperado al generar la gráfica: {e}") 