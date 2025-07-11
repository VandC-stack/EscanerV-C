#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Easter Egg: DOOM Simplificado
Se activa con Ctrl+Alt+D en la aplicación principal
"""
import pygame
import random
import math
import sys
import os
from typing import List, Tuple

class DoomEasterEgg:
    def __init__(self):
        pygame.init()
        self.width = 800
        self.height = 600
        self.screen = pygame.display.set_mode((self.width, self.height))
        pygame.display.set_caption("DOOM Easter Egg - V&C Scanner")
        
        # Colores del DOOM original
        self.BLACK = (0, 0, 0)
        self.RED = (255, 0, 0)
        self.GREEN = (0, 255, 0)
        self.BLUE = (0, 0, 255)
        self.YELLOW = (255, 255, 0)
        self.WHITE = (255, 255, 255)
        self.GRAY = (128, 128, 128)
        self.DARK_GRAY = (64, 64, 64)
        
        # Estado del juego
        self.player_x = 400
        self.player_y = 300
        self.player_angle = 0
        self.player_speed = 3
        self.rotation_speed = 0.1
        
        # Mapa simple (1 = pared, 0 = vacío)
        self.map_data = [
            [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
            [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
            [1,0,1,1,0,0,0,0,0,0,0,0,1,1,0,1],
            [1,0,1,0,0,0,0,0,0,0,0,0,0,1,0,1],
            [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
            [1,0,0,0,0,0,1,1,1,1,0,0,0,0,0,1],
            [1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,1],
            [1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,1],
            [1,0,0,0,0,0,1,1,1,1,0,0,0,0,0,1],
            [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
            [1,0,1,1,0,0,0,0,0,0,0,0,1,1,0,1],
            [1,0,1,0,0,0,0,0,0,0,0,0,0,1,0,1],
            [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
            [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
            [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
            [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]
        ]
        
        self.map_width = len(self.map_data[0])
        self.map_height = len(self.map_data)
        self.tile_size = 32
        
        # Enemigos simples
        self.enemies = [
            {'x': 200, 'y': 200, 'health': 100, 'color': self.RED},
            {'x': 600, 'y': 400, 'health': 100, 'color': self.RED},
            {'x': 400, 'y': 100, 'health': 100, 'color': self.RED}
        ]
        
        # Arma del jugador
        self.ammo = 30
        self.score = 0
        
        # Fuente para texto
        self.font = pygame.font.Font(None, 24)
        self.big_font = pygame.font.Font(None, 48)
        
        # Sonidos (simulados)
        self.sounds = {
            'shoot': None,
            'enemy_hit': None,
            'player_hit': None
        }
        
        # Estado del juego
        self.game_state = "playing"  # playing, paused, game_over, victory
        self.clock = pygame.time.Clock()
        
    def cast_ray(self, angle: float) -> Tuple[float, int]:
        """Lanza un rayo y calcula la distancia a la pared"""
        ray_x = self.player_x
        ray_y = self.player_y
        ray_cos = math.cos(angle)
        ray_sin = math.sin(angle)
        
        distance = 0
        hit_wall = False
        
        while not hit_wall and distance < 1000:
            distance += 1
            test_x = int(ray_x + ray_cos * distance)
            test_y = int(ray_y + ray_sin * distance)
            
            if (test_x < 0 or test_x >= self.map_width * self.tile_size or
                test_y < 0 or test_y >= self.map_height * self.tile_size):
                hit_wall = True
            elif self.map_data[test_y // self.tile_size][test_x // self.tile_size] == 1:
                hit_wall = True
        
        return distance, 1 if hit_wall else 0
    
    def render_3d(self):
        """Renderiza la vista 3D y los enemigos"""
        fov = math.pi / 3  # 60 grados
        ray_count = self.width
        ray_angle_step = fov / ray_count
        z_buffer = [float('inf')] * self.width  # Para ocultar enemigos detrás de paredes

        # Renderizar paredes
        for i in range(ray_count):
            ray_angle = self.player_angle - fov/2 + i * ray_angle_step
            distance, wall_type = self.cast_ray(ray_angle)
            distance *= math.cos(ray_angle - self.player_angle)  # Corregir fish-eye
            wall_height = int((self.height * 32) / distance) if distance > 0 else self.height
            wall_height = min(wall_height, self.height)
            wall_top = (self.height - wall_height) // 2
            wall_bottom = wall_top + wall_height
            if distance < 100:
                color = self.WHITE
            elif distance < 200:
                color = self.GRAY
            else:
                color = self.DARK_GRAY
            pygame.draw.line(self.screen, color, (i, wall_top), (i, wall_bottom))
            z_buffer[i] = distance

        # Renderizar enemigos (como rectángulos rojos)
        for enemy in self.enemies:
            # Vector del jugador al enemigo
            dx = enemy['x'] - self.player_x
            dy = enemy['y'] - self.player_y
            distance = math.sqrt(dx*dx + dy*dy)
            angle_to_enemy = math.atan2(dy, dx)
            relative_angle = angle_to_enemy - self.player_angle
            # Normalizar ángulo
            while relative_angle < -math.pi:
                relative_angle += 2*math.pi
            while relative_angle > math.pi:
                relative_angle -= 2*math.pi
            # Si el enemigo está en el campo de visión
            if abs(relative_angle) < fov/2:
                # Proyectar posición en pantalla
                screen_x = int((relative_angle + fov/2) / fov * self.width)
                # Verificar si hay pared entre el jugador y el enemigo
                if 0 <= screen_x < self.width and distance < z_buffer[screen_x]:
                    size = max(10, int(3000 / (distance+1)))  # Tamaño relativo a la distancia
                    center_y = self.height // 2
                    rect = pygame.Rect(screen_x - size//2, center_y - size//2, size, size)
                    pygame.draw.rect(self.screen, self.RED, rect)
    
    def render_minimap(self):
        """Renderiza el minimapa"""
        map_surface = pygame.Surface((200, 200))
        map_surface.fill(self.BLACK)
        
        # Dibujar mapa
        for y in range(self.map_height):
            for x in range(self.map_width):
                if self.map_data[y][x] == 1:
                    pygame.draw.rect(map_surface, self.GRAY, 
                                   (x * 10, y * 10, 10, 10))
        
        # Dibujar jugador
        pygame.draw.circle(map_surface, self.GREEN, 
                         (int(self.player_x / self.tile_size * 10), 
                          int(self.player_y / self.tile_size * 10)), 3)
        
        # Dibujar enemigos
        for enemy in self.enemies:
            pygame.draw.circle(map_surface, enemy['color'],
                             (int(enemy['x'] / self.tile_size * 10),
                              int(enemy['y'] / self.tile_size * 10)), 2)
        
        self.screen.blit(map_surface, (10, 10))
    
    def render_ui(self):
        """Renderiza la interfaz de usuario"""
        # HUD
        ammo_text = self.font.render(f"AMMO: {self.ammo}", True, self.WHITE)
        score_text = self.font.render(f"SCORE: {self.score}", True, self.WHITE)
        health_text = self.font.render("HEALTH: 100", True, self.GREEN)
        
        self.screen.blit(ammo_text, (10, self.height - 60))
        self.screen.blit(score_text, (10, self.height - 40))
        self.screen.blit(health_text, (10, self.height - 20))
        
        # Crosshair
        pygame.draw.circle(self.screen, self.RED, (self.width // 2, self.height // 2), 2)
        pygame.draw.circle(self.screen, self.RED, (self.width // 2, self.height // 2), 8, 1)
    
    def handle_input(self):
        """Maneja la entrada del usuario"""
        keys = pygame.key.get_pressed()
        
        # Movimiento
        if keys[pygame.K_w]:
            new_x = self.player_x + math.cos(self.player_angle) * self.player_speed
            new_y = self.player_y + math.sin(self.player_angle) * self.player_speed
            if self.is_valid_position(new_x, new_y):
                self.player_x = new_x
                self.player_y = new_y
        
        if keys[pygame.K_s]:
            new_x = self.player_x - math.cos(self.player_angle) * self.player_speed
            new_y = self.player_y - math.sin(self.player_angle) * self.player_speed
            if self.is_valid_position(new_x, new_y):
                self.player_x = new_x
                self.player_y = new_y
        
        if keys[pygame.K_a]:
            new_x = self.player_x + math.cos(self.player_angle - math.pi/2) * self.player_speed
            new_y = self.player_y + math.sin(self.player_angle - math.pi/2) * self.player_speed
            if self.is_valid_position(new_x, new_y):
                self.player_x = new_x
                self.player_y = new_y
        
        if keys[pygame.K_d]:
            new_x = self.player_x + math.cos(self.player_angle + math.pi/2) * self.player_speed
            new_y = self.player_y + math.sin(self.player_angle + math.pi/2) * self.player_speed
            if self.is_valid_position(new_x, new_y):
                self.player_x = new_x
                self.player_y = new_y
        
        # Rotación
        if keys[pygame.K_LEFT]:
            self.player_angle -= self.rotation_speed
        if keys[pygame.K_RIGHT]:
            self.player_angle += self.rotation_speed
    
    def is_valid_position(self, x: float, y: float) -> bool:
        """Verifica si una posición es válida (no dentro de una pared)"""
        map_x = int(x // self.tile_size)
        map_y = int(y // self.tile_size)
        
        if (map_x < 0 or map_x >= self.map_width or 
            map_y < 0 or map_y >= self.map_height):
            return False
        
        return self.map_data[map_y][map_x] == 0
    
    def shoot(self):
        """Dispara y verifica si golpea un enemigo"""
        if self.ammo <= 0:
            return
        
        self.ammo -= 1
        
        # Verificar si golpea un enemigo
        for enemy in self.enemies[:]:
            # Cálculo simple de distancia
            dx = enemy['x'] - self.player_x
            dy = enemy['y'] - self.player_y
            distance = math.sqrt(dx*dx + dy*dy)
            
            # Si está cerca y en la dirección correcta
            if distance < 100:
                angle_to_enemy = math.atan2(dy, dx)
                angle_diff = abs(angle_to_enemy - self.player_angle)
                
                if angle_diff < 0.3:  # Aproximadamente 17 grados
                    enemy['health'] -= 50
                    self.score += 100
                    
                    if enemy['health'] <= 0:
                        self.enemies.remove(enemy)
                        self.score += 500
    
    def update_enemies(self):
        """Actualiza el comportamiento de los enemigos"""
        for enemy in self.enemies:
            # Movimiento simple hacia el jugador
            dx = self.player_x - enemy['x']
            dy = self.player_y - enemy['y']
            distance = math.sqrt(dx*dx + dy*dy)
            
            if distance > 0:
                enemy['x'] += (dx / distance) * 1
                enemy['y'] += (dy / distance) * 1
    
    def render_game_over(self):
        """Renderiza la pantalla de game over"""
        self.screen.fill(self.BLACK)
        
        if not self.enemies:
            title = self.big_font.render("VICTORY!", True, self.GREEN)
            subtitle = self.font.render("Todos los demonios han sido eliminados", True, self.WHITE)
        else:
            title = self.big_font.render("GAME OVER", True, self.RED)
            subtitle = self.font.render("Has sido derrotado por los demonios", True, self.WHITE)
        
        score_text = self.font.render(f"Puntuación final: {self.score}", True, self.YELLOW)
        exit_text = self.font.render("Presiona ESC para salir", True, self.WHITE)
        
        self.screen.blit(title, (self.width//2 - title.get_width()//2, 200))
        self.screen.blit(subtitle, (self.width//2 - subtitle.get_width()//2, 260))
        self.screen.blit(score_text, (self.width//2 - score_text.get_width()//2, 300))
        self.screen.blit(exit_text, (self.width//2 - exit_text.get_width()//2, 400))
    
    def run(self):
        """Ejecuta el juego"""
        running = True
        
        while running:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_ESCAPE:
                        running = False
                    elif event.key == pygame.K_SPACE and self.game_state == "playing":
                        self.shoot()
                    elif event.key == pygame.K_p:
                        self.game_state = "paused" if self.game_state == "playing" else "playing"
            
            if self.game_state == "playing":
                self.handle_input()
                self.update_enemies()
                
                # Renderizar
                self.screen.fill(self.BLACK)
                self.render_3d()
                self.render_minimap()
                self.render_ui()
                
                # Verificar victoria/derrota
                if not self.enemies:
                    self.game_state = "victory"
                elif self.ammo <= 0 and len(self.enemies) > 0:
                    self.game_state = "game_over"
                    
            elif self.game_state in ["game_over", "victory"]:
                self.render_game_over()
            
            pygame.display.flip()
            self.clock.tick(60)
        
        pygame.quit()
        return self.score

def show_doom_easter_egg():
    """Función para mostrar el easter egg de DOOM"""
    print("🎮 ¡Easter Egg de DOOM activado!")
    print("Controles:")
    print("WASD - Movimiento")
    print("Flechas izquierda/derecha - Rotar")
    print("ESPACIO - Disparar")
    print("P - Pausar")
    print("ESC - Salir")
    print()
    
    try:
        game = DoomEasterEgg()
        final_score = game.run()
        print(f"🎯 Puntuación final: {final_score}")
        return final_score
    except Exception as e:
        print(f"❌ Error ejecutando el easter egg: {e}")
        print("Asegúrate de tener pygame instalado: pip install pygame")
        return 0

if __name__ == "__main__":
    show_doom_easter_egg() 