"use client";

import { useEffect, useRef } from "react";

type Particle = { x: number; y: number; size: number; brightness: number; pull: number; phase: number; age: number };

const arrivalRadius = 26;

/** Scattered points of light drifting into the Mac's notch: rough ideas going in. */
export function NotchField({ targetSelector }: { targetSelector: string }) {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = ref.current;
    const context = canvas?.getContext("2d");
    const target = document.querySelector(targetSelector);
    if (!canvas || !context || !target) return;

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let width = 0;
    let height = 0;
    let targetX = 0;
    let targetY = 0;
    let particles: Particle[] = [];
    let frame = 0;
    let last = 0;
    let isVisible = true;

    const spawn = (age: number): Particle => ({
      x: Math.random() * width,
      y: Math.random() * height,
      size: 0.6 + Math.random() * 1.1,
      brightness: 0.25 + Math.random() * 0.55,
      pull: 0.05 + Math.random() * 0.09,
      phase: Math.random() * Math.PI * 2,
      age,
    });

    const measure = () => {
      const bounds = canvas.getBoundingClientRect();
      const targetBounds = target.getBoundingClientRect();
      const scale = Math.min(window.devicePixelRatio || 1, 2);
      width = bounds.width;
      height = bounds.height;
      canvas.width = width * scale;
      canvas.height = height * scale;
      context.setTransform(scale, 0, 0, scale, 0, 0);
      targetX = targetBounds.left + targetBounds.width / 2 - bounds.left;
      targetY = targetBounds.top - bounds.top;
      particles = Array.from({ length: Math.min(120, Math.round((width * height) / 12000)) }, () => spawn(reduced ? 2 : Math.random() * 2));
    };

    const draw = () => {
      context.clearRect(0, 0, width, height);
      context.fillStyle = "#ffffff";
      for (const particle of particles) {
        const distance = Math.hypot(targetX - particle.x, targetY - particle.y);
        context.globalAlpha = particle.brightness * Math.min(1, particle.age / 1.4) * Math.min(1, distance / 220);
        context.beginPath();
        context.arc(particle.x, particle.y, particle.size, 0, Math.PI * 2);
        context.fill();
      }
    };

    const tick = (now: number) => {
      const elapsed = Math.min((now - last) / 1000, 0.05);
      last = now;
      particles = particles.map((particle) => {
        const distance = Math.hypot(targetX - particle.x, targetY - particle.y);
        if (distance < arrivalRadius) return spawn(0);
        particle.age += elapsed;
        // Pull strengthens near the notch, and a sideways wobble keeps the paths from looking like rays.
        const pull = particle.pull * (1 + 90 / (distance + 40));
        particle.x += (targetX - particle.x) * pull * elapsed + Math.sin(now / 900 + particle.phase) * 9 * elapsed;
        particle.y += (targetY - particle.y) * pull * elapsed + Math.cos(now / 1100 + particle.phase) * 9 * elapsed;
        return particle;
      });
      draw();
      frame = requestAnimationFrame(tick);
    };

    const start = () => {
      cancelAnimationFrame(frame);
      if (reduced || !isVisible) return;
      last = performance.now();
      frame = requestAnimationFrame(tick);
    };

    const setup = () => {
      measure();
      draw();
      start();
    };

    const resizeObserver = new ResizeObserver(setup);
    const visibilityObserver = new IntersectionObserver(([entry]) => {
      isVisible = entry.isIntersecting;
      start();
    });
    const idle = window.setTimeout(() => {
      setup();
      resizeObserver.observe(canvas);
      visibilityObserver.observe(canvas);
    }, 300);

    return () => {
      window.clearTimeout(idle);
      cancelAnimationFrame(frame);
      resizeObserver.disconnect();
      visibilityObserver.disconnect();
    };
  }, [targetSelector]);

  return <canvas ref={ref} aria-hidden="true" className="pointer-events-none absolute inset-0 size-full [mask-image:radial-gradient(ellipse_min(52vw,520px)_330px_at_50%_300px,transparent_72%,#000_100%)]" />;
}
